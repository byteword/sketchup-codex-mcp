# encoding: UTF-8
require 'minitest/autorun'
require_relative 'support/sketchup_double'
require_relative '../extension/su_pipe_probe/entity_browser'

class EntityBrowserTest < Minitest::Test
  def setup
    @model = SketchupDouble::Model.new
    @building = @model.add(100)
    @building.name = 'A동'
    @column = @model.add_child(@building, 101, 'ComponentInstance')
    @column.name = '기둥 A'
    @column.definition.name = 'COLUMN'
    @column.layer = @model.layers['구조']
    @other = @model.add(200, 'ComponentInstance')
    @other.name = 'B동'
    @model.add(300, 'Edge')
    @browser = SUPipeProbe::EntityBrowser.new(@model)
  end

  def find(args = {}, browser = @browser)
    browser.call('find_entities', {'type'=>'request', 'session_id'=>'session-a', 'model_id'=>'model-a'}.merge(args))
  end

  def children(ids = [], args = {})
    @browser.call('get_children', {'session_id'=>'session-a', 'model_id'=>'model-a', 'parent_path'=>ids}.merge(args))
  end

  def paths(result)
    result['items'].map { |item| item['instance_path'] }
  end

  def collect(args = {}, browser = @browser)
    pages, cursor = [], nil
    100.times do
      page = find(cursor ? args.merge('cursor'=>cursor) : args, browser)
      pages << page
      cursor = page['next_cursor']
      return pages unless cursor
    end
    flunk 'Cursor did not terminate'
  end

  def test_root_children_exclude_raw_geometry_and_do_not_recurse
    result = children
    assert_equal [%w[100], %w[200]], paths(result)
    assert result['complete']
    assert_equal 1, result['items'][0]['child_entity_count']
    assert result['items'].all? { |item| item['in_current_context'] }
  end

  def test_browse_parent_path_without_opening_or_modifying_model
    @model.selection.add([@other])
    camera = @model.active_view.camera
    result = children(['100'])
    assert_equal [%w[100 101]], paths(result)
    refute result['items'][0]['in_current_context']
    assert_equal [], result['current_context']
    assert_nil @model.active_path
    assert_equal [@other], @model.selection
    assert_same camera, @model.active_view.camera
    assert_equal 0, @model.starts
    refute @model.modified?
  end

  def test_name_matches_instance_or_definition_and_tag_is_exact
    assert_equal [%w[100 101]], paths(find('name'=>'기둥'))
    assert_equal [%w[100 101]], paths(find('name'=>'column', 'tag'=>'구조'))
    assert_empty find('name'=>'column', 'tag'=>'구')['items']
    assert_empty find('name'=>'^COLUMN$')['items']
    assert_empty find('name'=>'column', 'entity_type'=>'Group')['items']
  end

  def test_current_scope_and_model_scope_use_occurrence_context
    @model.active_path = [@building]
    @model.active_entities = @building.definition.entities
    result = find
    assert_equal [%w[100 101]], paths(result)
    assert result['items'][0]['in_current_context']
    assert_equal ['100'], result['root_path']
    result = find('scope'=>'model')
    assert_equal [%w[100], %w[100 101], %w[200]], paths(result)
    refute result['items'][0]['in_current_context']
    assert result['items'][1]['in_current_context']
    assert_equal ['100'], result['items'][1]['parent_path']
  end

  def test_shared_definitions_are_returned_once_per_occurrence
    @other.definition = @building.definition
    @building.definition.instances << @other
    result = find('name'=>'기둥')
    assert_equal [%w[100 101], %w[200 101]], paths(result)
    assert_equal ['101','101'], result['items'].map { |i| i['persistent_id'] }
    assert result['complete']
  end

  def test_page_limit_resumes_into_children_before_next_sibling
    pages = collect('limit'=>1)
    assert_equal [%w[100], %w[100 101], %w[200]], pages.flat_map { |p| paths(p) }
    assert pages.last['complete']
    assert_nil pages.last['next_cursor']
    assert pages.first['has_more']
    refute pages.first['complete']
    assert_equal 'page_limit', pages.first['stop_reason']
  end

  def test_children_cursor_and_empty_parent
    first = children([], 'limit'=>1)
    second = children([], 'limit'=>1, 'cursor'=>first['next_cursor'])
    assert_equal [%w[200]], paths(second)
    last = children([], 'cursor'=>second['next_cursor'])
    assert_empty last['items']
    assert last['complete']
    assert_empty children(['200'])['items']
    assert children(['200'])['complete']
  end

  def test_scan_limit_can_return_empty_page_with_continuation
    browser = SUPipeProbe::EntityBrowser.new(@model, nil, 1)
    pages = collect({'name'=>'B동'}, browser)
    assert_empty pages.first['items']
    assert_equal 'scan_limit', pages.first['stop_reason']
    assert pages.first['has_more']
    assert_equal [%w[200]], pages.flat_map { |p| paths(p) }
    assert pages.last['complete']
    assert pages.all? { |page| page['scanned'] <= 1 }
  end

  def test_time_limit_is_bounded_and_can_resume
    time = -0.1
    browser = SUPipeProbe::EntityBrowser.new(@model, lambda { time += 0.1 })
    pages = collect({}, browser)
    assert_equal 'time_limit', pages.first['stop_reason']
    assert_equal [%w[100], %w[100 101], %w[200]], pages.flat_map { |p| paths(p) }
    assert pages.last['complete']
  end

  def test_depth_limit_is_explicit_and_persists_across_pages
    first = find('max_depth'=>1, 'limit'=>1)
    assert first['omitted']['depth']
    last = find('max_depth'=>1, 'limit'=>25, 'cursor'=>first['next_cursor'])
    assert_equal [%w[200]], paths(last)
    refute last['complete']
    refute last['has_more']
    assert last['omitted']['depth']
  end

  def test_cyclic_definition_is_skipped_without_infinite_traversal
    @column.definition = @building.definition
    result = find
    assert result['omitted']['cycle']
    refute result['complete']
    refute result['has_more']
    assert_equal [%w[100], %w[100 101], %w[200]], paths(result)
  end

  def test_cursor_is_bound_to_filters_session_model_and_current_path
    cursor = find('limit'=>1)['next_cursor']
    [{'name'=>'different'}, {'model_id'=>'model-b'}, {'session_id'=>'session-b'}].each do |changes|
      assert_raises(ArgumentError) { find(changes.merge('cursor'=>cursor)) }
    end
    assert_raises(ArgumentError) { children([], 'cursor'=>cursor) }
    @model.active_path = [@building]
    assert_raises(ArgumentError) { find('scope'=>'model', 'cursor'=>cursor) }
  end

  def test_structure_change_invalidates_cursor_and_wrong_parent_is_rejected
    cursor = find('limit'=>1)['next_cursor']
    @model.add(400)
    assert_raises(ArgumentError) { find('cursor'=>cursor) }
    assert_raises(ArgumentError) { children(%w[200 101]) }
    @building.valid = false
    assert_raises(ArgumentError) { children(['100']) }
  end

  def test_invalid_cursor_and_invalid_ruby_arguments_are_rejected
    ['not base64', '', 'x'*8193, Base64.strict_encode64('{}')].each do |cursor|
      assert_raises(ArgumentError) { find('cursor'=>cursor) }
    end
    [{'limit'=>true}, {'limit'=>26}, {'max_depth'=>0}, {'name'=>''}, {'tag'=>nil}, {'entity_type'=>'Edge'}, {'scope'=>'selection'}].each do |args|
      assert_raises(ArgumentError) { find(args) }
    end
    assert_raises(ArgumentError) { children(['0']) }
    assert_raises(ArgumentError) { children(Array.new(32, '100')) }
  end

  def test_hidden_locked_and_unicode_results_are_direct_and_clipped
    @column.hidden = @column.locked = true
    @column.name = '🙂' * 256 + 'needle'
    result = find('name'=>'needle')['items'].first
    assert result['hidden']
    assert result['locked']
    assert result['text_truncated']
    assert_equal 256, result['name'].length
    assert_equal '구조', result['tag']
  end

  def test_byte_limit_keeps_pages_and_resumes_every_result
    25.times do |i|
      entity = @model.add(400+i)
      entity.name = entity.definition.name = '🙂'*256
      entity.layer = SketchupDouble::Named.new('🙂'*256, true)
    end
    pages = collect('name'=>'🙂', 'limit'=>25)
    assert_equal 'byte_limit', pages.first['stop_reason']
    assert_equal 25, pages.sum { |p| p['returned'] }
    assert pages.all? { |p| JSON.generate(p).bytesize < 60_000 }
    assert pages.last['complete']
    assert_equal 25, pages.flat_map { |p| p['items'].map { |i| i['instance_path'] } }.uniq.length
  end
end
