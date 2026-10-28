# encoding: UTF-8
require 'securerandom'

module SUPipeProbe
  # A document lifetime is not a Ruby wrapper lifetime: Windows can reuse the
  # active Model object for File > New/Open. Never derive identity from a path
  # or Model#guid (which changes when an edited model is saved).
  class ModelIdentity < Sketchup::AppObserver
    def initialize(&changed)
      @changed = changed
    end

    def id_for(model)
      renew(model) unless @model.equal?(model) && @id
      @id
    end

    def expectsStartupModelNotifications
      true
    end

    def onNewModel(model)
      renew(model)
      nil
    end

    def onOpenModel(model)
      renew(model)
      nil
    end

    def onActivateModel(model)
      id_for(model)
      nil
    end

    private

    def renew(model)
      @model = model
      @id = SecureRandom.uuid
      @changed.call if @changed
      @id
    end
  end
end
