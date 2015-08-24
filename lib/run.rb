require 'slack-notifier'
require 'redis'
require 'github_api'
require 'pp'


def get_usernames(text)
  text.scan(/@([[:alnum:]][[:alnum:]\-]+)/).map(&:first)
end

def redis_connection
  @redis_connection ||= Redis.new(url: ENV['REDIS_URL'])
end

def github_info
  {
    token: redis_connection.get('oauth_token'),
    org: redis_connection.get('github_org')
  }
end

# { github => slack }
def memtion_mapping
  @memtion_mapping ||= (
    hash = {}
    (redis_connection.get('mapping_mapping') || '').split("\n").each do |line|
      github, slack = line.split(',').map(&:strip)
      hash[github] = slack
    end
    hash
  )
end

def slack_notifier
  @slack_notifier ||= Slack::Notifier.new ENV['SLACK_HOOK']
end

pp memtion_mapping

def notify_slack(obj)
  mentioned_slack_users = obj[:mentioned_users].map { |user| memtion_mapping[user] }.compact
  return if mentioned_slack_users.count == 0

  message = "[#{obj[:repo].name}##{obj[:issue].number}] <#{obj[:issue].html_url}|#{obj[:issue].title}>\n"
  message += '-- Reviewer -->'
  mentioned_slack_users.each do |user|
    message += " <@#{user}>"
  end
  slack_notifier.ping message
end

github = Github.new oauth_token: github_info[:token], auto_pagination: true

github.repos(org: github_info[:org]).list.each do |repo|
  puts repo.name
  github.issues.list(user: github_info[:org], repo: repo.name).each do |issue|
    mentioned_users = []

    puts "  [#{issue.number}] #{issue.title}"

    github.issues.comments.list(user: 'quelon', repo: 'quelon-api', number: issue.number).each do |comment|
      puts '    ' + comment.user.login
      puts '      ' + comment.body.gsub(/\n/, "\n      ")

      mentioned_users |= get_usernames(comment.body)
      mentioned_users.delete(comment.user.login)
    end

    puts "  ** mentioned_users: #{mentioned_users.join(',')}"

    notify_slack({
      repo: repo,
      issue: issue,
      mentioned_users: ['tadyjp']
    }) if mentioned_users.count > 0
  end
end
