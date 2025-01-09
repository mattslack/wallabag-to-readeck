require "net/http"
require "sinatra"

configure(:development) {
  set :bind, "0.0.0.0"
}

before do
  @http = Net::HTTP.new(ENV["READECK"], port)
  @http.use_ssl = false
end

before "/api/*" do
  @token = request.env["HTTP_AUTHORIZATION"]
  halt 403, "Unauthorized" unless @token
end

# Wallabag API specifies a PUT here, but koreader wallabag performs a POST
post "/oauth/v2/token" do
  request.body.rewind
  data = JSON.parse request.body.read
  username = data["username"]
  password = data["password"]

  authenticate username, password
end

put "/oauth/v2/token" do
  username = params[:username]
  password = params[:password]

  authenticate username, password
end

# get a list of entries
get "/api/entries.json" do
  limit = params["perPage"] || 10
  offset = (params["page"] || "1").to_i - 1
  path = "/api/bookmarks?is_archived=false&type=article&sort=-created&limit=#{limit}&offset=#{offset}&labels=-pdf&site=-youtube.com"
  logger.info path
  response = @http.send_request("GET", path, nil, {
    authorization: @token
  })

  items = JSON.parse(response.body).map do |bookmark|
    {
      is_archived: bookmark["is_archived"],
      is_starred: bookmark["is_marked"],
      username: "",
      user_email: "",
      user_id: session[:user_uid],
      tags: bookmark["labels"],
      is_public: false,
      id: bookmark["id"],
      uid: bookmark["id"],
      title: bookmark["title"],
      url: bookmark["url"],
      hashed_url: "",
      given_url: "",
      hashed_given_url: "",
      archived_at: "",
      content: "",
      created_at: bookmark["created"],
      updated_at: "",
      published_at: bookmark["published"],
      published_by: bookmark["authors"],
      starred_at: "",
      annotations: [],
      mimetype: "",
      language: bookmark["lang"],
      reading_time: "",
      domain_name: bookmark["site"]&.gsub(/^[^:]+\/\//, ""),
      preview_picture: bookmark.dig("resources", "thumbnail", "src") || nil,
      http_status: response.code || 200,
      headers: [],
      links: []
    }
  end

  content_type :json
  JSON.generate({
    page: response["Current-Page"],
    pages: response["Total-Pages"],
    total: response["Total-Count"],
    _embedded: {
      items: items
    }
  })
end

# Get an epub of a bookmark
get "/api/entries/:id/export.epub" do
  response = @http.send_request("GET", "/api/bookmarks/#{params[:id]}/article.epub", nil, {
    authorization: @token
  })
  halt response.code unless response.is_a? Net::HTTPSuccess
  status 200
  headers \
    "Content-Type" => "application/epub+zip"
  body response.body
end

# create a bookmark
post "/api/entries.json" do
  wallabag_data = JSON.parse request.body.read
  data = {}

  data[:url] = wallabag_data["url"]
  data[:title] = wallabag_data["title"] if wallabag_data.has_key? "archive"
  data[:labels] = wallabag_data["tags"].split(",") if wallabag_data.has_key? "tags"

  response = @http.send_request("POST", "/api/bookmarks/", data.to_json, {
    authorization: @token,
    "Content-Type": "application/json"
  })
  halt response.code unless response.is_a? Net::HTTPSuccess

  response_body = {
    href: response["Location"],
    id: response["Bookmark-Id"]
  }

  status 200
  body response_body.to_json
end

# update a bookmark
patch "/api/entries/*.json" do |id|
  response_body = update_bookmark(id, request)
  status 200
  body response_body.to_json
end

# tag a bookmark
post "/api/entries/:id/tags.json" do
  logger.info request.body
  response_body = update_bookmark(params[:id], request)
  status 200
  body response_body.to_json
end

def authenticate(username, password)
  halt 401 unless username && password
  response = @http.send_request("POST", "/api/auth",
    JSON.generate({
      application: "api_doc",
      password: password,
      username: username
    }), {
      "Content-Type": "application/json"
    })
  halt response.code unless response.is_a? Net::HTTPSuccess
  body = JSON.parse(response.body)

  content_type :json
  {access_token: body["token"], token_type: "bearer", expires_in: 60}.to_json
end

def port
  ENV["READECK_PORT"] || 8000
end

def update_bookmark(id, request)
  wallabag_data = JSON.parse request.body.read
  data = {}

  data[:is_archived] = wallabag_data["archive"] == 1 if wallabag_data.has_key? "archive"
  data[:labels] = wallabag_data["tags"].split(",") if wallabag_data.has_key? "tags"
  logger.info wallabag_data

  response = @http.send_request("PATCH", "/api/bookmarks/#{id}", data.to_json, {
    authorization: @token,
    "Content-Type": "application/json"
  })
  halt response.code unless response.is_a? Net::HTTPSuccess

  data = JSON.parse(response.body)

  {
    href: response.uri,
    id: data["id"],
    uid: data["id"],
    is_archived: (data["is_archived"] == true) ? 1 : 0,
    is_deleted: 0,
    is_starred: (data["is_marked"] == true) ? 1 : 0,
    tags: data["labels"],
    title: data["title"],
    updated_at: data["updated"]
  }
end
