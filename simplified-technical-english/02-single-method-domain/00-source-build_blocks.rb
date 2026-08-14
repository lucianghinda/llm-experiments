    def build_blocks(records, timestamp_method, thread_key)
      blocks = records.group_by { |record| thread_key.call(record) }.values.map do |thread_records|
        ordered_records = thread_records.sort_by(&timestamp_method)
        root = ordered_records.find do |record|
          thread_key.call(record) == root_identifier(record)
        end || ordered_records.first
        DraftBlock.new(root: root, thread_members: ordered_records - [root])
      end

      blocks.sort_by { |block| block.root.public_send(timestamp_method) }
    end
