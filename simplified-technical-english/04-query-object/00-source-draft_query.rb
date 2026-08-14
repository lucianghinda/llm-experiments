# frozen_string_literal: true

class Edition::DraftQuery
  DraftBlock = Data.define(:root, :thread_members)

  def initialize(edition)
    @edition = edition
  end

  def call
    empty_sections.tap do |sections|
      add_blocks(sections, bluesky_blocks)
      add_blocks(sections, twitter_blocks)
    end
  end

  private

    attr_reader :edition

    def empty_sections
      Newsletter::SectionTaxonomy.ordered_top_level.index_with { [] }
    end

    def window
      edition.start_date.beginning_of_day...edition.end_date.tomorrow.beginning_of_day
    end

    def bluesky_blocks
      records = edition.organisation.bluesky_posts.
                where(post_created_at: window, hidden: false).
                where.not(id: excluded_bluesky_ids).
                then { |scope| without_bluesky_root_exclusions(scope) }.
                includes(:url_titles,
                  author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS },
                  snapshot_image_attachment: :blob).
                order(:post_created_at).
                to_a

      build_blocks(records, :post_created_at, method(:bluesky_thread_key))
    end

    def twitter_blocks
      records = edition.organisation.tweets.
                where(tweet_created_at: window, hidden: false).
                where.not(id: excluded_twitter_ids).
                then { |scope| without_twitter_root_exclusions(scope) }.
                includes(:url_titles,
                  author: { author: Author::PLATFORM_ACCOUNT_ASSOCIATIONS },
                  snapshot_image_attachment: :blob).
                order(:tweet_created_at).
                to_a

      build_blocks(records, :tweet_created_at, method(:twitter_thread_key))
    end

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

    def root_identifier(record)
      case record
      when Bluesky::Post
        record.uri
      when Twitter::Tweet
        record.tweet_id
      end
    end

    def add_blocks(sections, blocks)
      blocks.each do |block|
        section_key = Newsletter::SectionTaxonomy.for(block.root.section).fetch(:key)
        next unless sections.key?(section_key)

        sections.fetch(section_key) << block
      end
    end

    def bluesky_thread_key(post)
      post.thread_root_uri.presence || post.uri
    end

    def twitter_thread_key(tweet)
      tweet.conversation_id.presence || tweet.tweet_id
    end

    def without_bluesky_root_exclusions(scope)
      return scope if excluded_bluesky_thread_roots.empty?

      scope.where.not(thread_root_uri: excluded_bluesky_thread_roots)
    end

    def without_twitter_root_exclusions(scope)
      return scope if excluded_twitter_thread_roots.empty?

      scope.where.not(conversation_id: excluded_twitter_thread_roots)
    end

    def excluded_bluesky_ids
      @_excluded_bluesky_ids ||= excluded_records(Bluesky::Post).map(&:id)
    end

    def excluded_bluesky_thread_roots
      @_excluded_bluesky_thread_roots ||= excluded_records(Bluesky::Post).filter_map do |post|
        post.thread_root_uri if post.thread_root_uri.present? && post.thread_root_uri == post.uri
      end
    end

    def excluded_twitter_ids
      @_excluded_twitter_ids ||= excluded_records(Twitter::Tweet).map(&:id)
    end

    def excluded_twitter_thread_roots
      @_excluded_twitter_thread_roots ||= excluded_records(Twitter::Tweet).filter_map do |tweet|
        tweet.conversation_id if tweet.conversation_id.present? && tweet.conversation_id == tweet.tweet_id
      end
    end

    def excluded_records(model)
      edition.edition_exclusions.where(excludable_type: model.name).includes(:excludable).map(&:excludable)
    end
end
