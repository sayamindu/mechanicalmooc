
require 'mooc'
require 'seq-email'
require 'digest/sha1'

module GroupConfirm

  def self.send_to_all(users)
    users.each do |email|
      self.send_confirm_email(email)      
    end
  end

  def self.send_confirm_email(email)
    body = File.read('./emails/group-confirm3.html')
    link_template = "http://mechanicalmooc.org/confirm?email=%EMAIL%&auth_token=%AUTH_TOKEN%"
    link = link_template.sub('%EMAIL%', email).sub('%AUTH_TOKEN%', email_auth(email))

    se = SequenceEmail.new
    se.subject = "Last chance to confirm your group!"
    se.body = body.sub('%CONFIRM_LINK%', link)
    se.tags << "group-confirm-test"
    se.send_email_to(email)
  end
  
  def self.confirm(email, auth_token)
    return false unless valid? email, auth_token
    user = User.last(:email => email)
    return false unless user
    user.group_confirmation = true
    user.save
  end

  def self.valid?(email, auth_token)
    email_auth(email) == auth_token
  end

  def self.email_auth(email)
    Digest::SHA1.hexdigest email + ENV['MMOOC_CONFIRM_SALT']
  end
end
