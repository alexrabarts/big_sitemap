class TestModel
  def to_param
    object_id
  end

  class << self
    def count_for_sitemap
      self.find_for_sitemap.size
    end

    def find_for_sitemap(options={})
      instances = []
      num_times = options.delete(:limit) || self.num_items
      num_times.times { instances.push(self.new) }
      instances
    end
  end
end