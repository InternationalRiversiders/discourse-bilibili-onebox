# Run with rails runner. Default is a dry run; BILI_METADATA_APPLY=1 writes cooked HTML only.
require 'fileutils'
require 'digest'
engine = Onebox::Engine::BilibiliOnebox
apply = ENV['BILI_METADATA_APPLY'] == '1'
$stdout.sync = true
backup = nil
if apply
  dir = '/shared/rollouts/bilibili-mobile-metadata'
  FileUtils.mkdir_p(dir, mode: 0700)
  backup = File.open("#{dir}/#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}.jsonl", File::WRONLY | File::CREAT | File::EXCL, 0600)
end
stats = Hash.new(0)
metadata = {}
models = [Post]
models << Chat::Message if defined?(Chat::Message)
models.each do |model|
  # Repair the reported test topics first, then work backwards through history.
  scope = model.unscoped.where("cooked LIKE '%player.bilibili.com%'")
  ids = scope.order(id: :desc).pluck(:id)
  if model == Post
    priority = scope.where(topic_id: [3386, 31848]).pluck(:id)
    ids = priority + (ids - priority)
  end
  ids.each do |id|
    row = model.unscoped.find_by(id: id)
    next unless row
    original = row.cooked
    doc = Nokogiri::HTML.fragment(original)
    changed = 0
    doc.css('iframe[src]').each do |frame|
      uri = URI.parse(frame['src']) rescue next
      next unless uri.host == 'player.bilibili.com' && uri.path == '/player.html'
      params = URI.decode_www_form(uri.query.to_s).to_h rescue next
      next if params['cid'].to_s.match?(/\A[1-9]\d*\z/)
      vid = params['bvid'].presence || "av#{params['aid']}"
      next unless engine.valid_video_id?(vid)
      unless metadata.key?(vid)
        metadata[vid] = engine.video_metadata(vid)
        stats[:videos_checked] += 1
        sleep 0.5 # Avoid sending a historical import burst upstream.
      end
      info = metadata[vid]
      page = params['p'] || params['page'] || '1'
      part = info && page.match?(/\A[1-9]\d*\z/) && info['pages'].find { |p| p['page'] == page.to_i }
      unless part
        stats[:unresolved_frames] += 1
        next
      end
      params.merge!('aid' => info['aid'].to_s, 'bvid' => info['bvid'], 'cid' => part['cid'].to_s)
      uri.query = URI.encode_www_form(params)
      frame['src'] = uri.to_s
      changed += 1
    end
    next if changed.zero?
    saved = false
    if apply
      row.with_lock do
        # Metadata fetching happens outside the lock; never overwrite a concurrent edit.
        if row.cooked == original
          raw_field = model == Post ? 'raw' : 'message'
          raw_hash = Digest::SHA256.hexdigest(row[raw_field].to_s)
          backup.puts(JSON.generate(table: model.table_name, id: id, cooked: original))
          backup.flush
          row.update_columns(cooked: doc.to_html)
          row.sync_first_post_caches if model == Post
          raise 'Original text changed' unless Digest::SHA256.hexdigest(row.reload[raw_field].to_s) == raw_hash
          saved = true
        else
          stats[:concurrent_edits_skipped] += 1
        end
      end
      if saved && row.deleted_at.nil?
        if model == Post
          row.publish_change_to_clients!(:rebaked)
        else
          Chat::Publisher.publish_edit!(row.chat_channel, row)
        end
      end
    end
    stats[:rows] += 1 if saved || !apply
    stats[:frames] += changed if saved || !apply
    puts({table: model.table_name, id: id, frames: changed, saved: saved}.to_json)
  end
end
if apply
  cache = Discourse.cache
  (cache.keys('onebox__*bilibili.com*') + cache.keys('onebox__*b23.tv*')).uniq.each do |key|
    cache.delete(key.delete_prefix("#{cache.namespace}:"))
    stats[:cache_invalidated] += 1
  end
end
backup&.close
puts({apply: apply, summary: stats}.to_json)
