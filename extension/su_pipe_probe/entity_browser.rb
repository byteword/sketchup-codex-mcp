# encoding: UTF-8
require 'json'
require 'base64'
require 'digest'
require 'time'

module SUPipeProbe
  # Read-only, bounded traversal of instance occurrences, not unique definitions.
  class EntityBrowser
    SCAN_LIMIT = 20_000
    PAGE_BUDGET = 40_000
    MAX_PATH = 32
    CURSOR_LIMIT = 8192

    def initialize(model, clock = nil, scan_limit = SCAN_LIMIT)
      @model = model
      @clock = clock || lambda { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @scan_limit = scan_limit
    end

    def call(method, args)
      raise ArgumentError, 'Unknown discovery method' unless %w[find_entities get_children].include?(method)
      limit = args.fetch('limit', 10)
      integer(limit, 1, 25)
      current = (@model.active_path || []).map { |e| pid(e) }
      path(current, MAX_PATH)
      if method == 'get_children'
        root = args.fetch('parent_path')
        path(root, MAX_PATH - 1)
        depth = 1
        filters = {}
      else
        scope = args.fetch('scope', 'current')
        raise ArgumentError, 'scope must be current or model' unless %w[current model].include?(scope)
        root = scope == 'current' ? current : []
        raise ArgumentError, 'Current edit path is too deep; use model scope or browse a shallower parent' if root.length >= MAX_PATH
        depth = args.fetch('max_depth', 8)
        integer(depth, 1, MAX_PATH)
        filters = {}
        %w[name tag entity_type].each { |key| filters[key] = args[key] if args.key?(key) }
        %w[name tag].each do |key|
          value = filters[key]
          if filters.key?(key) && !(value.is_a?(String) && value.length.between?(1, 256) && !value.include?("\0"))
            raise ArgumentError, 'Invalid text filter'
          end
        end
        raise ArgumentError, 'Invalid type filter' if filters.key?('entity_type') && !%w[Group ComponentInstance].include?(filters['entity_type'])
      end
      collection, definitions = resolve(root)
      key = Digest::SHA256.hexdigest(JSON.generate([method, args['session_id'], args['model_id'], root, current, filters.sort, depth]))
      frames, skipped = restore(args['cursor'], key, collection, definitions, root)
      raise ArgumentError, 'Invalid cursor depth' if frames.length > depth
      items, bytes, scanned = [], 0, 0
      reason = nil
      deadline = @clock.call + 0.25
      prune(frames)
      until frames.empty?
        if items.length >= limit
          reason = 'page_limit'
          break
        end
        if scanned >= @scan_limit || @clock.call >= deadline
          reason = scanned >= @scan_limit ? 'scan_limit' : 'time_limit'
          break
        end
        frame = frames.last
        entity = frame[:entities][frame[:index]]
        if entity && entity.valid? && %w[Group ComponentInstance].include?(entity.typename)
          id = pid(entity)
          if id
            item = describe(entity, frame[:path], current)
            if matches(entity, filters)
              size = JSON.generate(item).bytesize
              if bytes + size > PAGE_BUDGET
                raise ArgumentError, 'One result exceeds the response budget' if items.empty?
                reason = 'byte_limit'
                break
              end
              items << item
              bytes += size
            end
            frame[:index] += 1
            scanned += 1
            # Direct-child browsing is complete without examining grandchildren.
            if method == 'find_entities' && entity.definition.entities.length > 0
              definition = entity.definition
              if frame[:definitions].include?(definition)
                skipped['cycle'] = true
              elsif frames.length >= depth || frame[:path].length + 1 >= MAX_PATH
                skipped['depth'] = true
              else
                frames << make_frame(definition.entities, frame[:path] + [id], frame[:definitions] + [definition], id)
              end
            end
          else
            skipped['missing_id'] = true
            frame[:index] += 1
            scanned += 1
          end
        else
          frame[:index] += 1
          scanned += 1
        end
        prune(frames)
      end
      cursor = frames.empty? ? nil : encode(key, frames, skipped)
      {'queried_at' => Time.now.utc.iso8601(3), 'root_path' => root, 'current_context' => current,
       'items' => items, 'returned' => items.length, 'scanned' => scanned,
       'next_cursor' => cursor, 'has_more' => !cursor.nil?,
       'complete' => cursor.nil? && skipped.values.none?, 'stop_reason' => reason,
       'omitted' => skipped, 'max_depth' => depth,
       'notes' => ['Live pages, not a snapshot. Restart after model structure changes; never change filters with a cursor.',
         'Groups/components only. Each instance occurrence has a full instance_path, including shared definitions.',
         'name matches instance OR definition name (case-insensitive substring); tag matches the exact direct tag name.',
         'Flags are direct assignments. Hidden/locked ancestors can still affect commands and appearance.',
         'Use persistent_id and parent_path for commands only after refreshing the current edit context. No edit path is opened automatically.',
         'child_entity_count counts all direct entity types, including raw faces/edges.']}
    end

    private

    def integer(value, minimum, maximum)
      raise ArgumentError, 'Invalid integer or range' unless value.is_a?(Integer) && value.between?(minimum, maximum)
    end

    def path(value, maximum)
      unless value.is_a?(Array) && value.length <= maximum && value.all? { |id| id.is_a?(String) && id.match(/\A[1-9][0-9]{0,18}\z/) }
        raise ArgumentError, 'Invalid instance path'
      end
    end

    def pid(entity)
      value = entity.persistent_id
      value.is_a?(Integer) && value > 0 && value.to_s.length <= 19 ? value.to_s : nil
    rescue StandardError, NotImplementedError
      nil
    end

    def resolve(ids)
      entities, definitions = @model.entities, []
      ids.each do |id|
        entity = @model.find_entity_by_persistent_id(id.to_i)
        unless entity && entity.valid? && %w[Group ComponentInstance].include?(entity.typename) && entity.parent == entities.parent
          raise ArgumentError, 'Instance path is stale or does not belong to this parent; restart discovery'
        end
        definition = entity.definition
        raise ArgumentError, 'Cyclic instance path' if definitions.include?(definition)
        definitions << definition
        entities = definition.entities
      end
      [entities, definitions]
    end

    def make_frame(entities, ids, definitions, via = nil)
      {:entities => entities, :path => ids, :definitions => definitions, :via => via, :index => 0, :count => entities.length}
    end

    def restore(cursor, key, entities, definitions, root)
      skipped = {'depth' => false, 'cycle' => false, 'missing_id' => false}
      return [[make_frame(entities, root, definitions)], skipped] if cursor.nil?
      raise ArgumentError, 'Invalid discovery cursor; restart without cursor' unless cursor.is_a?(String) && cursor.bytesize.between?(1, CURSOR_LIMIT)
      begin
        data = JSON.parse(Base64.strict_decode64(cursor), :max_nesting => 8)
        raise ArgumentError unless data.is_a?(Hash) && data['v'] == 1 && data['key'] == key
        saved = data['frames']
        raise ArgumentError unless saved.is_a?(Array) && saved.length.between?(1, MAX_PATH - root.length)
        raise ArgumentError unless data['omitted'].is_a?(Hash) && data['omitted'].keys.sort == skipped.keys.sort
        data['omitted'].each { |k,v| raise ArgumentError unless v == true || v == false; skipped[k] = v }
        frames = []
        saved.each_with_index do |entry, i|
          raise ArgumentError unless entry.is_a?(Hash)
          if i > 0
            parent = frames.last
            raise ArgumentError unless parent[:index] > 0
            entity = parent[:entities][parent[:index] - 1]
            unless entity && entity.valid? && %w[Group ComponentInstance].include?(entity.typename) && pid(entity) == entry['via']
              raise ArgumentError
            end
            definition = entity.definition
            raise ArgumentError if definitions.include?(definition)
            root = root + [entry['via']]
            definitions = definitions + [definition]
            entities = definition.entities
          else
            raise ArgumentError unless entry['via'].nil?
          end
          integer(entry['index'], 0, entities.length)
          raise ArgumentError unless entry['count'] == entities.length
          frame = make_frame(entities, root, definitions, entry['via'])
          frame[:index] = entry['index']
          frames << frame
        end
        [frames, skipped]
      rescue StandardError
        raise ArgumentError, 'Invalid, mismatched or stale discovery cursor; restart without cursor'
      end
    end

    def prune(frames)
      frames.pop while !frames.empty? && frames.last[:index] >= frames.last[:entities].length
    end

    def encode(key, frames, skipped)
      saved = frames.map { |f| {'via'=>f[:via], 'index'=>f[:index], 'count'=>f[:count]} }
      cursor = Base64.strict_encode64(JSON.generate('v'=>1, 'key'=>key, 'frames'=>saved, 'omitted'=>skipped))
      raise ArgumentError, 'Cursor exceeds the response budget' if cursor.bytesize > CURSOR_LIMIT
      cursor
    end

    def matches(entity, filters)
      return false if filters['entity_type'] && filters['entity_type'] != entity.typename
      return false if filters['tag'] && filters['tag'] != entity.layer.name.to_s
      if filters['name']
        text = filters['name'].downcase
        return false unless entity.name.to_s.downcase.include?(text) || entity.definition.name.to_s.downcase.include?(text)
      end
      true
    end

    def describe(entity, parent, current)
      values = [entity.name.to_s, entity.definition.name.to_s, entity.layer.name.to_s]
      {'persistent_id' => pid(entity), 'type' => entity.typename,
       'name' => values[0][0, 256], 'definition_name' => values[1][0, 256], 'tag' => values[2][0, 256],
       'text_truncated' => values.any? { |text| text.length > 256 },
       'hidden' => entity.hidden?, 'locked' => entity.locked?,
       'parent_path' => parent, 'instance_path' => parent + [pid(entity)],
       'in_current_context' => parent == current,
       'child_entity_count' => entity.definition.entities.length}
    end
  end
end
