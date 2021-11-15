# Mattermost Group Importer

## About

This script automates the process of linking LDAP groups to teams and channels. This is useful for setting up LDAP Group Sync with a large number of groups, or for setting up a demo environment. You can also set up teams and channels with the script, making the setup process even faster.

## How it works

The script reads from the groups, teams, and channels from `conf.yml`. If there are teams and channels configured, it will attempt to create them or modify them to match the provided configuration.

Then it will iterate over the groups, looking them up via their display name and then linking them with teams and channels.

**Note:** This has been tested against OpenLDAP version 1.5 and there may be issues using it with Active Directory especially when using `ObjectGUID` as the Group ID Attribute. If you are using Active Directory, have a problem, and have an AD server for me to test with please create an issue.

## Instructions

### 1. Set up Mattermost Authentication

First, either modify the `docker-compose.yml` *OR* create a `.env` file to set the Mattermost URL and Token environment variables to allow administrator access to the Mattermost server.

**`docker-compose.yml`**

```yaml
version: "3.7"

services:
  mattermost-group-importer:
    build: .
    volumes:
      - ./conf:/usr/src/app/conf
    environment:
      - MATTERMOST_URL=${MATTERMOST_URL}
      - MATTERMOST_TOKEN=${MATTERMOST_TOKEN}
```

**`.env` File**

```
MATTERMOST_URL=https://mattermost.example.com
MATTERMOST_TOKEN=y34xh885nfnppjiteruu76n93r
```

### 2. Configure Teams, Channels, and Groups

Next, Copy `conf/conf.sample.yml` to `conf/conf.yml` and configure the teams, channels, and groups you want to link. 

**Teams Config**

```yaml
teams:
  team-name:
    DisplayName: "Team Display Name"
    Description: "Team Description"
    Email: "user@example.com" # Email of the creator of the team
    Public: true # Omit to make team Invite Only
```

**Channels Config**

```yaml
channels:
  team-name: # Team to create channels in
    channel-name: # name of the channel
      DisplayName: "Channel Display Name"
      Public: true # Omit to make the channel private
```

**Groups Config**

```yaml
groups:
  admin: # This corresponds to the value in the Group Display Name attribute
    teams: # Users will be added to this team
    	- a-team
    team_admins: # Users will be admins for this team
      - team-name
    channels: # Users will be added to this team and channel
      - a-team:a-channel
    channel_admins: # Users will be channel admins
      - team-name:channel-name
    channels:
      - doop:public-relations
```

More teams, channels, and groups can be added as necessary

### 3. Run `docker-compose up`

This can be run on any system that can connect to the Mattermost server via HTTP.