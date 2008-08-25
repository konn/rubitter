require "time"
class <<Twitter
  def define_struct(name, *attrs, &init)
    k = Class.new
    k.__send__(:attr_reader, *attrs)
    k.__send__(:define_method, :initialize){|arg|
      case arg
      when REXML::Element
        init_with_elem(arg)
      when String
        stat = REXML::Document.new(arg)
        init_with_elem(stat.elements[1])
      when Hash
        attrs.each{|i|
          instance_variable_set("@#{i.to_s}", arg[i.intern])
        }
      when Array
        arg.each_with_index{|v, i|
          instance_variable_set("@#{attrs[i]}", i)
        }
      end
    }
    
    k.__send__(:define_method, :init_with_elem){|elem|
      attrs.each{|i|
        el = elem.elements[i.to_s]
        el = el.text if el
        instance_variable_set("@#{i.to_s}", el)
      }
      init_sub(elem)
    }
    k.__send__(:define_method, :init_sub, &init)
    const_set(name, k)
  end
end

class Twitter
  define_struct(:Status, :created_at, :id, :text, :source, 
                :in_reply_to, :in_reply_to_user_id, :user){|elem|
    @created_at = Time.parse(@created_at.to_s) if @created_at
    @id = @id.to_i
    @user = User.new(elem.elements["user"])
  }
  
  define_struct(:DirectMessage, :text, :sender_id, :recipient_id, :created_at,
                :sender_screen_name, :recipient_screen_name, :id){|elem|
    @sender_id = @sender_id.to_i
    @recipient_id = @recipient_id.to_i
    @created_at &&= Time.parse(@created_at)
  }

  define_struct(:User,
    :id, :name, :screen_name, :location, :description, 
    :profile_image_url, :url, :protected, :profile_background_color, 
    :profile_text_color, :profile_link_color, :profile_sidebar_fill_color, 
    :profile_sidebar_border_color, :friends_count, :followers_count, 
    :favourites_count, :statuses_count, :status){|elem|
    ints = %w[
      @id @statuses_count @friends_count @followers_count @favourites_count @statuses_count
    ]
    ints.each{|v|
      instance_variable_set(v, instance_variable_get(v).to_i)
    }
    @status = Status.new(elem.elements["status"])
    @protected = @protected.downcase != "false"
  }
end