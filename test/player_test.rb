# Run inside an isolated Discourse database: bundle exec rails runner PATH
require 'minitest/autorun'

class BilibiliPlayerTest < Minitest::Test
  Engine = Onebox::Engine::BilibiliOnebox

  def replace_method(owner, name, replacement)
    original = owner.method(name)
    owner.define_singleton_method(name, replacement)
    yield
  ensure
    owner.define_singleton_method(name, original)
  end

  def document(id, page = nil)
    Nokogiri::HTML.fragment(Engine.iframe_html(id, page))
  end

  def parameters(doc)
    URI.decode_www_form(URI.parse(doc.at_css('iframe')['src']).query).to_h
  end

  def test_av_player_without_extra_link
    doc = document('av117460158190918')
    assert_equal '117460158190918', parameters(doc)['aid']
    refute parameters(doc).key?('bvid')
    assert_empty doc.css('a')
    assert_equal '0', parameters(doc)['autoplay']
  end

  def test_bv_and_part_preserved
    doc = document('BV1GJ411x7h7', '4')
    assert_equal 'BV1GJ411x7h7', parameters(doc)['bvid']
    assert_equal '4', parameters(doc)['p']
    refute parameters(doc).key?('aid')
    assert_includes doc.at_css('iframe')['allow'], 'fullscreen'
  end

  def test_invalid_ids_and_parts_are_not_interpolated
    ['', 'av0', 'av-1', 'BVx', "BV1GJ411x7h7' onload='x"].each { |id| assert_nil Engine.iframe_html(id) }
    ['0', '-1', "1' onload='x"].each { |p| refute parameters(document('av10186015', p)).key?('p') }
    assert_equal '10186015', parameters(document('AV10186015'))['aid']
  end

  def test_urls_and_shared_link_part
    assert_equal 'av10186015', Engine.extract_video_id('https://m.bilibili.com/video/av10186015/?p=2')
    assert_nil Engine.extract_video_id('https://www.bilibili.com/video/nope')
    assert_nil Engine.extract_video_id('https://evil.example/video/av10186015')
    assert_equal '2', Engine.extract_video_page('https://www.bilibili.com/video/av10186015?tracking=x&p=2')
    assert_nil Engine.extract_video_page('https://www.bilibili.com/video/av10186015?p=0')
  end

  def test_cached_short_links_keep_id_kind_and_part
    key = 'bilibili-short-link:BiliTest123'
    Discourse.cache.write(key, { video_id: 'av10186015', page: '2', page_checked: true })
    result = Engine.expand_short_links('https://b23.tv/BiliTest123')
    assert_equal 'https://www.bilibili.com/video/av10186015?p=2', result
    id = Engine.extract_video_id(result)
    assert_equal '10186015', parameters(document(id, Engine.extract_video_page(result)))['aid']
    assert_nil Engine.normalize_short_link_cache(video_id: "bad'", page_checked: true)
  ensure
    Discourse.cache.delete(key)
  end

  def test_plain_text_and_markdown_are_unchanged
    ['test', "no match\n普通文字\n", '[视频](https://www.bilibili.com/video/av10186015)', '`https://www.bilibili.com/video/av10186015`'].each do |raw|
      assert_equal raw, Engine.wrap_inline_bilibili_links(raw)
    end
  end

  def test_two_inline_links_preserve_all_surrounding_text_once
    a = 'https://www.bilibili.com/video/av10186015/'
    b = 'https://www.bilibili.com/video/BV1GJ411x7h7/'
    raw = "before #{a} middle #{b} after"
    result = Engine.wrap_inline_bilibili_links(raw)
    assert_equal raw, result.delete("\n")
    assert_equal 1, result.scan(a).size
    assert_equal 1, result.scan(b).size
    assert_equal result, Engine.wrap_inline_bilibili_links(result)
  end

  def test_onebox_engine_uses_aid_for_test_topic
    html = Engine.new('https://www.bilibili.com/video/av10186015').to_html
    assert_equal '10186015', parameters(Nokogiri::HTML.fragment(html))['aid']
  end

  def test_post_processing_corrects_bare_link_without_extra_link
    doc = Nokogiri::HTML.fragment('<p><a href="https://www.bilibili.com/video/av10186015">https://www.bilibili.com/video/av10186015</a></p>')
    DiscourseEvent.trigger(:post_process_cooked, doc, Post.new)
    assert_equal '10186015', parameters(doc)['aid']
    assert_equal 1, doc.css('iframe').size
    assert_equal 0, doc.css('a').size
    DiscourseEvent.trigger(:post_process_cooked, doc, Post.new)
    assert_equal 1, doc.css('iframe').size
    assert_equal 0, doc.css('a').size
    refute doc.at_css('iframe').ancestors.any? { |node| node.name == 'p' }
  end
  def test_short_redirect_never_fetches_blocked_destination
    key = 'bilibili-short-link:RedirectTest123'
    Discourse.cache.delete(key)
    calls = []
    get = lambda do |url, **_opts|
      calls << url
      raise 'Must not fetch destination video page' unless calls.size == 1
      Excon::Response.new(status: 302, headers: { location: 'https://www.bilibili.com/video/av10186015?p=4&tracking=test' })
    end
    replace_method(FinalDestination::SSRFDetector, :lookup_and_filter_ips, ->(*) { ['93.184.216.34'] }) do
      replace_method(Excon, :get, get) do
        info = Engine.resolve_short_link_info('https://b23.tv/RedirectTest123/')
        assert_equal 'av10186015', info[:video_id]
        assert_equal '4', info[:page]
        assert_equal 1, calls.size
        assert_equal info, Engine.resolve_short_link_info('https://b23.tv/RedirectTest123')
        assert_equal 1, calls.size
      end
    end
  ensure
    Discourse.cache.delete(key)
  end

  def test_create_and_edit_expand_cached_short_links
    key = 'bilibili-short-link:EditTest123'
    Discourse.cache.write(key, { video_id: 'av10186015', page: '2', page_checked: true })
    user = Discourse.system_user
    category = Category.create!(name: "Bili test #{SecureRandom.hex(4)}", user: user)
    post = PostCreator.new(user, title: "Bilibili regression #{SecureRandom.hex(6)}", raw: 'https://b23.tv/EditTest123', category: category.id).create!
    assert post.persisted?, post.errors.full_messages.join(', ')
    assert_equal 'https://www.bilibili.com/video/av10186015?p=2', post.reload.raw
    PostRevisor.new(post).revise!(user, { raw: "edited text\n\nhttps://b23.tv/EditTest123" })
    assert_equal "edited text\n\nhttps://www.bilibili.com/video/av10186015?p=2", post.reload.raw
  ensure
    Discourse.cache.delete(key)
  end

end
