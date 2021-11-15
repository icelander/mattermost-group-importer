require 'httparty'
require 'uri'
require 'cgi'

class MattermostApi
	include HTTParty
	attr_accessor :groups

	format :json
	# debug_output STDOUT
	
	def initialize(config)
		@options = {
			headers: {
				'Content-Type' => 'application/json'
			},
			verify: false
		}

		if config.key?(:url) && !config[:url].nil?
			url = config[:url]
		else
			raise 'MattermostAPI: URL is required'
		end

		unless url.end_with? '/'
			url = url + '/'
		end

		unless url_valid?(url)
			raise "URL #{url} is invalid"
		end

		@base_uri = url + 'api/v4/'

		token = nil

		
		if config.key?(:auth_token) && config[:auth_token] != ''
			$log.debug("MattermostApi: Auth Token set in config: #{config[:auth_token]}")
			token = config[:auth_token]
		else
			unless config.key?('username')
				raise "MattermostApi: username is required"
			end

			# Use password login
			$log.debug("MattermostApi: Auth Token not set in config, using password")
			if (config.key?('password'))
				token = self.get_login_token(config['username'], config['password'])
			else
				raise "MattermostApi: Password or Auth Token is required"
			end
		end

		if token.nil?
			raise 'MattermostApi: Could not set auth token.'
		else
			$log.debug("MattermostApi: Setting Auth Token to: #{token}")
			@options[:headers]['Authorization'] = "Bearer #{token}"
		end

		@options[:body] = nil
		@options[:query] = nil
	end

	def get_login_token(login_id, password)
		$log.debug("Logging in with #{login_id} / #{password}")
		payload = {login_id: login_id, password: password}
		url = "#{@base_uri}users/login"

		response = self.class.post(url, {body: payload.to_json, headers: {'Content-Type' => 'application/json'}})
		
		if response.code == 200 || response.code == 201
			return response.headers['token']
		else
			$log.error("Could not login to Mattermost")
		end
		
		return nil
	end

	def get_current_user
		get_url('users/me')
	end

	def create_post(channel_id, message, root_id=nil, file_ids=nil, props=nil)
		url = 'posts'

		payload = {
			channel_id: channel_id,
			message: message,
			root_id: root_id,
			props: props,
			file_ids: file_ids
		}

		return post_data(url, payload)
	end

	def get_ldap_groups(page: 0, per_page: 60, query: "")
		url = sprintf('ldap/groups?page=%dper_page=%dq=%s', page, per_page, CGI.escape(query).gsub("+", "%20"))
		return self.get_url(url)
	end

	def get_team_id_by_name(team_name)
		response = self.get_team_by_name(team_name)

		if response.nil?
			return nil
		else
			return response['id']
		end
	end

	def get_team_by_name(team_name)
		url = "teams/name/#{self.cgi_escape(team_name)}"
		response = self.get_url(url)
		
		return response
	end

	def update_team_by_id(team_id, team)
		team['id'] = team_id
		url = "teams/#{team_id}"
		response = self.put_data(url, team)

		if response.code >= 200 && response.code <= 300 # Successful
			return JSON.parse(response.to_s)
		else
			$log.warn("Mattermost API error #{url} - #{response.code}: #{response.to_s}")
			return nil
		end
	end

	def update_channel_by_id(channel_id, channel)
		channel['id'] = channel_id
		url = "channels/#{channel_id}"
		response = self.put_data(url, channel)

		if response.code >= 200 && response.code <= 300 # Successful
			return JSON.parse(response.to_s)
		else
			$log.warn("Mattermost API error #{url} - #{response.code}: #{response.to_s}")
			return nil
		end
	end

	def create_channel(team_id, channel_name, display_name, type)
		payload = {
			team_id: team_id,
			name: channel_name,
			display_name: display_name,
			type: type
		}

		self.post_data('channels', payload)
	end


	def create_team(team_name, display_name, type)
		type.upcase!

		if ! ['I', 'O'].include? type
			raise "Invalid team type: #{type}"
		end

		payload = {
			name: team_name,
			display_name: display_name,
			type: type
		}

		request = self.post_data('teams', payload)
	end

	def get_ldap_group_by_name(group_name)
		url = 'ldap/groups'
		query = {q: group_name}

		response = self.get_url(url, query)

		if response['count'] != 1
			return nil
		else
			return response['groups'][0]
		end
	end

	def cgi_escape(string)
		CGI.escape(string).gsub('+', '%20')
	end

	def link_ldap_group(group_remote_id)
		$log.debug ("Linking group with remote_id #{group_remote_id}")
		url = "ldap/groups/#{self.cgi_escape(group_remote_id)}/link"
		self.post_data(url, nil)
	end

	def link_team_to_group(team_id, group_id, auto_add=false)
		url = "groups/#{group_id}/teams/#{team_id}/link"
		groupteam = {
			team_id: team_id,
  			group_id: group_id,
  			auto_add: auto_add
		}
		response = self.post_data(url, groupteam)
		# pp response
		return response
	end

	def make_group_team_admins(team_id, group_id)
		url = "groups/#{group_id}/teams/#{team_id}/patch"
		payload = {scheme_admin: true}
		self.put_data(url, payload)
	end

	def make_group_channel_admins(channel_id, group_id)
		url = "groups/#{group_id}/channels/#{channel_id}/patch"
		payload = {scheme_admin: true}
		self.put_data(url, payload)
	end

	def link_channel_to_group(channel_id, group_id, auto_add=false)
		url = "groups/#{group_id}/channels/#{channel_id}/link"
		groupchannel = {
			channel_id: channel_id,
  			group_id: group_id,
  			auto_add: auto_add
		}
		response = self.post_data(url, groupchannel)
		# pp response
		return response
	end


	def get_channel_id_by_name(provided_channel_name, provided_team_name=nil)
		$log.debug("channel name: #{provided_channel_name}")
		response = self.get_channel_by_name(provided_channel_name)

		if response.nil?
			return nil
		else
			return response['id']
		end
	end

	def get_channel_by_name(provided_channel_name, provided_team_name=nil)
		if provided_team_name.nil? and provided_channel_name.include?(':')
			(team_name, channel_name) = provided_channel_name.split(':')
		else
			team_name = provided_team_name
			channel_name = provided_channel_name
		end

		if team_name.nil? || channel_name.include?(':')
			raise "Invalid channel and team name: #{provided_channel_name} #{team_name}"
		end

		url = "teams/name/#{team_name}/channels/name/#{channel_name}"

		response = self.get_url(url)
		
		return response
	end

	private

	def url_valid?(url)
		url = URI.parse(url) rescue false
	end

	def get_url(url, query=nil)
		@options[:query] = nil
		
		unless query.nil?
			@options[:query] = query
		end

		response = self.class.get("#{@base_uri}#{url}", @options)

		@options[:query] = nil

		if response.code >= 200 && response.code <= 300 # Successful
			JSON.parse(response.to_s)	
		else
			return nil
		end		
	end

	def post_data(request_url, payload)
		
		@options[:body] = nil
		
		unless payload.nil? 
			@options[:body] = payload.to_json
		end
		
		response = self.class.post("#{@base_uri}#{request_url}", @options)

		@options[:body] = nil

		if response.code >= 200 && response.code <= 300 # Successful
			return JSON.parse(response.to_s)	
		else
			$log.warn("Mattermost API error #{response.code}: #{response.to_s}")
			return nil
		end
	end

	def put_data(request_url, payload)
		options = @options
		options[:body] = payload.to_json

		self.class.put("#{@base_uri}#{request_url}", options)
	end
end