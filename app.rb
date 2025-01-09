require "net/http"
require "sinatra"

configure(:development) {
  set :bind, "0.0.0.0"
}

before do
  @http = Net::HTTP.new(ENV["READECK"], port)
  @http.use_ssl = false
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
