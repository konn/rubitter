#!/usr/local/bin/ruby -Ku
require 'date'
require 'enumerator'
require 'rexml/document'
require 'uri'
require 'net/http'

Net::HTTP.version_1_2

module Identity

  def to_i
    @id
  end

  def id
    @id
  end

end

class Twitter
  attr_reader :user, :pass
  autoload :Status, "struct2.rb"
  autoload :User, "struct2.rb"
  autoload :DirectMessage, "struct2.rb"

  def self.public_timeline
    new("", "").public_timeline
  end

  def self.define_get(kind)
    define_method("#{kind}_get"){|*arg|
      mtd, args, auth = arg
      auth = true if auth.nil?
      get("#{kind}/#{mtd}.xml", args, auth)
    }
  end

  
  def self.define_id_proc(name, rclass, rproc, arg)
    define_method(name){|id|
      id = id[:id] if id.is_a?(Hash)
      id = id.id if id.is_a?(Identity)
      rclass.new __send__(rproc, "#{arg}/#{id}", *arg)
    }
  end

  def self.define_timeline(prefix, auth=true)
    define_method("#{prefix}_timeline"){|*opts|
      if opts.empty?
        opts = {}
      else
        opts = opts[0]
        opts = {:id => opts} unless opts.is_a?(Hash)
      end
      src = statuses_get("#{prefix}_timeline", opts, auth)
      proc_statuses(src)
    }
  end

  def self.define_proc_structs(parent, child)
    kn = child.split("_").map{|a| a.capitalize}.join
    define_method("proc_#{parent.gsub(/-/,'_')}"){|src|
      doc = REXML::Document.new(src)
      stats = doc.enum_for(:each_element, "#{parent}/#{child}")
      return stats.map{|st|  self.class.const_get(kn).new(st)}
    }
  end

  def initialize(user, pass)
    @user = user
    @pass = pass
    @cookie = nil
  end

  def request(mtd, path, args, auth=true, whole=false)
    mtd = mtd.to_s.capitalize
    Net::HTTP.start("twitter.com", 80) {|http|
      query = args.map{|k, v| "#{URI.escape(k.to_s)}=#{URI.escape(v.to_s)}"}.join("&")
      req = Net::HTTP.const_get(mtd).new("/#{path}?#{query}")
      if @cookie
        req["cookie"] = @cookie
      end
      req.basic_auth @user, @pass if auth
      resp = http.request(req)
      return resp if whole
      case resp.code.to_i
      when 200, 304
        resp.body
      when 302
        p resp['location']
      else
        raise "#{resp.code} #{resp.msg}"
      end
    }
  end
  private :request

  def post(path, args, whole=false)
    request("post", path, args, true, whole)
  end
  private :post

  def get(path, args, auth, whole=false)
    request("get", path, args, auth, whole)
  end
  private :get

  define_get(:direct_messages)
  define_get(:statuses)
  define_get(:favourings)
  define_get(:notifications)
  define_get(:friendships)

  define_timeline(:public, false)
  define_timeline(:friends)
  define_timeline(:user)

  def show(id)
    src = get("users/show/#{id}.xml", {}, true)
    return User.new(src)
  end
  alias get_user show

  def update(status)
    up = post("statuses/update.xml", {:status=>status})
    Status.new up
  end
  alias update_status update

  def replies(opts={})
    proc_statuses statuses_get("replies", opts, true)
  end

  define_id_proc(:destroy_status, Status, :statuses_get, "destroy")
  alias delete_status destroy_status

  define_proc_structs("users", "user")
  define_proc_structs("direct-messages", "direct_message")
  define_proc_structs("statuses", "status")

  def friends(id=@user)
    id = id[:id] if id.is_a?(Hash)
    id = id.id if id.is_a?(Identity)
    src = statuses_get("friends/#{id}", {}, true)
    proc_users(src)
  end

  def followers(opts={})
    opts[:lite] = opts unless opts.is_a?(Hash)
    opts[:lite] = opts[:lite] ? "true" : "false"
    src = statuses_get("followers", opts, true)
    proc_users src
  end

  def features
    proc_users statuses_get("features", {}, true)
  end

  def direct_messages
    proc_direct_messages get("direct_messages.xml", {}, true)
  end

  def sent
    proc_direct_messages direct_messages_get("sent", {}, true)
  end

  def new_direct_message(*args)
    opts = {}
    fst , snd = args
    if fst.is_a?(Hash)
      opts[:user] = fst[:user]
      opts[:text] = fst[:text].to_s
    else
      opts[:user] = fst
      opts[:text] = snd.to_s
    end
    opts[:user] = opts[:user].id if opts[:user].is_a?(Identity)
    DirectMessage.new post("direct_messages/new.xml", opts)
  end

  define_id_proc(:destroy_direct_message , DirectMessage, :direct_messages_get, "destroy")

  define_id_proc(:create_friend, User, :friendships_get, "create")
  define_id_proc(:destroy_friend, User, :friendships_get, "destroy")

  def account_get(mtd, args, whole=true)
    get("account/#{mtd}", args, false, whole)
  end

  def verify_credentials
    if resp = account_get("verify_credentials", {})
      @cookie = resp["set-cookie"]
      return true
    else
      raise [resp.code, resp.msg].join(" ")
    end
  end

  def end_session
    if resp = account_get("end_session", {})
      @cookie = resp["set-cookie"]
      return true
    else
      raise [resp.code, resp.msg].join(" ")
    end
  end

  def archive(opts={})
    opts[:page] = opts unless opts.is_a?(Hash)
    proc_statuses account_get("archive", opts, false)
  end
  
  def favorites(*args)
    opts = {}
    if args[0].is_a? Hash
      opts[:id] = args[0][:id]
      opts[:page] = args[0].fetch(:page, 1)
    else
      opts[:id] = args[0]
      if args[1].is_a? Hash
        opts[:page] = args[1].fetch(:page, 1)
      else
        opts[:page] = args.fetch(1, 1)
      end
    end
    path = opts[:id] ? "favourings/#{opts[:id]}.xml" : "favorites.xml"
    opts.delete(:id)
    proc_statuses get(path, opts, true)
  end

  define_id_proc(:create_favorite, Status, :favourings_get, "create")
  define_id_proc(:destroy_favorite, Status, :favourings_get, "destroy")

  define_id_proc(:im_follow, User, :notifications_get, "follow")
  define_id_proc(:im_follow, User, :notifications_get, "leave")

end