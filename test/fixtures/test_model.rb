class TestModel
  def to_param
    object_id
  end

  def change_frequency
    'monthly'
  end

  def priority
    0.8
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
  end
end