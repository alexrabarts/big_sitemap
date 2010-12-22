class TestModel
  def to_param
    id #|| object_id
  end

  def id
    @id ||= TestModel.current_id += 1
  end

  def change_frequency
    'monthly'
  end

  def priority
    0.8
  end

  def updated_at
    Time.at(1000000000)
  end

  class << self
    def count_for_sitemap
      self.find_for_sitemap.size
    end

    def num_items
      10
    end

    def find_for_sitemap(options={})
      instances = []
      num_times = options.delete(:limit) || self.num_items
      num_times.times { instances.push(self.new) }
      instances
    end

    attr_writer :current_id

    def current_id
      @current_id ||= 0
    end
  end
end