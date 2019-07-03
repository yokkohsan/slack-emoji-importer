require 'highline/import'
require 'mechanize'
require 'json'

class Processor
  DEFAULT_IMPORT_IMG_DIR = File.expand_path(File.dirname(__FILE__)) + "/images"

  def initialize(import_img_dir: nil)
    @page = nil
    @agent = Mechanize.new
    @import_img_dir = import_img_dir || DEFAULT_IMPORT_IMG_DIR
  end
  attr_accessor :page, :agent, :team_name, :token

  def import
    move_to_emoji_page
    upload
  end

  private

  def login
    @team_name = ask('Your slack team name(subdomain): ')
    email      = ask('Login email: ')
    password   = ask('Login password(hidden): ') { |q| q.echo = false }

    emoji_page_url = "https://#{team_name}.slack.com/customize/emoji"

    page = agent.get(emoji_page_url)
    page.form.email = email
    page.form.password = password
    @page = page.form.submit
    @token = @page.body[/(?<=api_token":")[^"]+/]
  end

  def enter_two_factor_authentication_code
    page.form['2fa_code'] = ask('Your two factor authentication code: ')
    @page = page.form.submit
    @token = @page.body[/(?<=api_token":")[^"]+/]
  end

  def move_to_emoji_page
    loop do
      if page && page.form['signin_2fa']
        enter_two_factor_authentication_code
      else
        login
      end

      break if page.title.include?('絵文字') || page.title.include?('Emoji')
      puts 'Login failure. Please try again.'
      puts
    end
  end

  def upload
    emojis = list_emojis
    files = Dir.glob([@import_img_dir + "/*.png", @import_img_dir + "/*.gif"])
    len = files.length
    puts "total files = #{len}"
    files.each.with_index(1) do |path, i|
      basename = File.basename(path, '.*')

      # skip if already exists
      if emojis.include?(basename)
        puts "(#{i}/#{len}) #{basename} already exists, skip"
        next
      end

      puts "(#{i}/#{len}) importing #{basename}..."

      params = {
        name: basename,
        image: File.new(path),
        mode: 'data',
        token: token
      }

      begin
        agent.post("https://#{team_name}.slack.com/api/emoji.add", params)
      rescue
        for j in 0..100
          print "."
          sleep(1)
        end
        puts
        retry
      end
    end
  end

  def list_emojis
    emojis = []
    loop.with_index(1) do |_, n|
      params = { query: '', page: n, count: 100, token: token }
      res = JSON.parse(agent.post("https://#{team_name}.slack.com/api/emoji.adminList", params).body)
      raise res['error'] if res['error']
      emojis.push(*res['emoji'].map { |e| e['name'] })
      break if res['paging']['pages'] == n || res['paging']['pages'] == 0
    end
    emojis
  end
end

Processor.new.import
puts 'Done!'
