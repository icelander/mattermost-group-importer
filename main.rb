#!/usr/bin/env ruby

require 'yaml'
require './mattermost.rb'

$log = Logger.new(STDOUT)
$log.level = Logger::INFO

yaml = YAML.load(File.read("conf/conf.yml"))

config = yaml['config'].freeze
groups = yaml['groups'].freeze
teams = yaml['teams'].freeze
channels = yaml['channels'].freeze

class String
  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end
end

if ENV['MATTERMOST_URL'].nil? || ENV['MATTERMOST_TOKEN'].nil?
	$log.fatal("MATTERMOST_URL and MATTEMROST_TOKEN environment variables are required")
	exit 1
else
	url = ENV['MATTERMOST_URL']
	token = ENV['MATTERMOST_TOKEN']
end

mm = MattermostApi.new({url: url, auth_token: token})

teams.each do |team_name, info|
	team = mm.get_team_by_name(team_name)
	info['type'] = 'I'
	if info['Public']
		info['type'] = 'O'
	end

	if team.nil?
		$log.info("Creating team #{team_name}")
		team = mm.create_team(team_name, info['DisplayName'], info['type'])
	else
		$log.debug("Found team #{team_name}. Updating Values")
		
		# Compare existing team and update as required
		info.each do |k, v|
			if team.key? k.underscore
				if team[k.underscore] != v
					team[k.underscore] = v
				end	
			end
		end
		
		mm.update_team_by_id(team['id'], team)
		$log.info("Team #{team_name} Updated!")
	end
	
end

channels.each do |team_name, c|
	team = mm.get_team_by_name(team_name)

	if team.nil?
		$log.warn("Couldn't find team #{team_name} while creating the channel, skipping...")
		next
	end

	c.each do |channel_name, info|
		full_name = "#{team_name}:#{channel_name}"


		info['type'] = 'P'
		if info['Public']
			info['type'] = 'O'
		end

		channel = mm.get_channel_by_name(full_name)

		if channel.nil?
			$log.info("Creating channel #{full_name}")
			mm.create_channel(team['id'], channel_name, info['DisplayName'], info['type'])
		else
			$log.debug("Found channel #{full_name}. Updating values")

			# Compare existing team and update as required
			info.each do |k, v|
				if channel.key? k.underscore
					if channel[k.underscore] != v
						channel[k.underscore] = v
					end	
				end
			end
			
			if ! mm.update_channel_by_id(channel['id'], channel).nil?
				$log.info("Channel #{full_name} Updated!")
			else
				$log.error("Couldn't update #{full_name}")
			end
		end

	end
end

groups.each do |group_name,links|
	group = mm.get_ldap_group_by_name(group_name)

	if group.nil?
		$log.warn("Couldn't find group with name #{group_name}, skipping")
		next
	end

	# If it doesn't have a `mattermost_group_id` we need to link it
	if group['mattermost_group_id'].nil? && links.length > 0
		$log.info("#{group_name} is not linked with Mattermost. Linking...")
		mm.link_ldap_group(group['primary_key'])
		# Reload it to get the mattermost_group_id
		group = mm.get_ldap_group_by_name(group_name)
	end

	links.each do |link_type, items|
		case link_type
		when 'teams', 'team_admins'
			items.each do |team_name|
				team_id = mm.get_team_id_by_name(team_name)

				if team_id.nil?
					$log.warn("Couldn't find team with name: #{team_name}, skipping...")
					next
				end

				$log.info("Linking team #{team_name} with #{group_name}")
				mm.link_team_to_group(team_id, group['mattermost_group_id'], true)

				if link_type == 'team_admins'
					$log.info("Making #{group_name} team admins for #{team_name}")
					mm.make_group_team_admins(team_id, group['mattermost_group_id'])
				end
			end
		when 'channels', 'channel_admins'
			items.each do |channel_name|
				channel_id = mm.get_channel_id_by_name(channel_name)

				if channel_id.nil?
					$log.warn("Couldn't find channel with name: #{channel_name}")
					next
				end

				$log.info("Linking channel #{channel_name} with #{group_name}")
				mm.link_channel_to_group(channel_id, group['mattermost_group_id'], true)

				if link_type == 'channel_admins'
					$log.info("Making #{group_name} channel admins for #{channel_name}")
					mm.make_group_channel_admins(channel_id, group['mattermost_group_id'])
				end
			end
		else
			$log.warn("Invalid link type: #{link_type}. Valid ones are team, team_admin, channel, channel_admin")
		end
	end
end