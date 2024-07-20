require 'net/http'
require 'uri'
require 'json'
require 'open-uri'
require 'zip'
require 'base64'

class FaviconGenerator < Rails::Generators::Base
  PATH_UNIQUE_KEY = '/Dfv87ZbNh2'

  class_option(:timeout, type: :numeric, aliases: '-t', default: 30)
  class_option(:namespace, type: :string, aliases: '-n', default: nil)

  def generate_favicon
    timeout = options[:timeout]
    namespace = options[:namespace]

    payload = prepare_payload(namespace)
    response = send_post_request(payload, timeout)

    zip = response['favicon_generation_result']['favicon']['package_url']
    favicon_folder_path = ['app/assets/images', namespace, 'favicon'].compact.join('/')
    FileUtils.mkdir_p(favicon_folder_path)

    Dir.mktmpdir 'rfg' do |tmp_dir|
      download_package zip, tmp_dir
      Dir["#{tmp_dir}/*.*"].each do |file|
        content = File.binread(file)
        new_ext = ''
        if ['.json', '.xml'].include? File.extname(file)
          content = replace_url_by_asset_path content
          new_ext = '.erb'
        end
        create_file "#{favicon_folder_path}/#{File.basename file}#{new_ext}", content
      end
    end

    favicon_html_erb_folder = namespace.nil? ? "application" : namespace
    create_file "app/views/#{favicon_html_erb_folder}/_favicon.html.erb",
      replace_url_by_asset_path(response['favicon_generation_result']['favicon']['html_code'])

    web_app_manifest_path = "config/initializers/web_app_manifest.rb"
    unless File.exist? web_app_manifest_path
      create_file web_app_manifest_path,
        File.read(File.dirname(__FILE__) + '/web_app_manifest_initializer.txt')
    end
  end

  private

  def prepare_payload(namespace)
    favicon_config_folder = "#{File.expand_path('.')}/config/rails_real_favicon"
    if namespace
      favicon_config_folder += "/#{namespace}"
    end
    
    favicon_json_path = "#{favicon_config_folder}/favicon.json"
    payload = JSON.parse File.read(favicon_json_path)

    master_pic_path = "#{favicon_config_folder}/#{payload['master_picture']}"
    master_pic_enc = Base64.encode64(File.binread(master_pic_path))

    payload['api_key'] = '04641dc33598f5463c2f1ff49dd9e4a617559f4b'

    payload['files_location'] = Hash.new
    payload['files_location']['type'] = 'path'
    payload['files_location']['path'] = PATH_UNIQUE_KEY

    payload['master_picture'] = Hash.new
    payload['master_picture']['type'] = 'inline'
    payload['master_picture']['content'] = master_pic_enc

    return payload
  end

  def send_post_request(payload, timeout)
    uri = URI.parse("https://realfavicongenerator.net/api/favicon")
    return Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: timeout) do |http|
      request = Net::HTTP::Post.new uri
      request.body = { favicon_generation: payload }.to_json
      request["Content-Type"] = "application/json"
      begin
        JSON.parse(http.request(request).body)
      rescue Net::ReadTimeout
        raise RuntimeError.new("Operation timed out after #{timeout} seconds, pass a `-t` option for a longer timeout")
      end
    end
  end

  def download_package(package_url, output_dir)
    file = Tempfile.new('fav_package')
    file.close
    download_file package_url, file.path
    extract_zip file.path(), output_dir
  end

  def download_file(url, local_path)
    if File.directory?(local_path)
      uri = URI.parse(url)
      local_path += '/' + File.basename(uri.path)
    end

    File.open(local_path, "wb") do |saved_file|
      URI.open(url, "rb") do |read_file|
        saved_file.write(read_file.read)
      end
    end
  end

  def extract_zip(zip_path, output_dir)
    Zip::File.open zip_path do |zip_file|
      zip_file.each do |f|
        f_path=File.join  output_dir, f.name
        FileUtils.mkdir_p  File.dirname(f_path)
        zip_file.extract(f, f_path) unless File.exist? f_path
      end
    end
  end

  def replace_url_by_asset_path(content)
    repl = "\"<%= asset_path 'favicon\\k<path>' %>\""
    content.gsub(/"#{PATH_UNIQUE_KEY}(?<path>[^"]+)"/) do |s|
      s.gsub!(/\\\//, '/')
      s.gsub(/"#{PATH_UNIQUE_KEY}(?<path>[^"]+)"/, repl)
    end
  end

end
