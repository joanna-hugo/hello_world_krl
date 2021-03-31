ruleset manage_sensors{
  meta {
    name "Managae Sensors"
    description "Manages several childs, each representing a sensor"
    author "Joanna Hugo"
    shares sensors, showChildren, getRIDs, children, subscriptions, all_temperatures//accessible from GUI
    provides ruleset_event //internal
    configure using
      authToken = ""
      accountSID = ""
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias subs
    use module org.twilio.sdk alias sdk
  }

  global{
    default_location = "home"
    default_threshold = 100
    default_phone_number= "18001234567"

    children = function(){
      ent:children
    }  

    ruleset_event = function(URL, eci, child_id, child_role){
      { 
        "eci": eci, 
        "eid": "install-ruleset", // can be anything, used for correlation
        "domain": "wrangler", "type": "install_ruleset_request",
        "attrs": {
          "url": URL,
          "config": {
            "authToken": <<#{authToken}>>.klog("authToken: "),
            "accountSID" : <<#{accountSID}>>.klog("accountSID: ")
          },
          "child_id": child_id,
          "child_role":child_role
        }
      }.klog("ruleset event returning: ")
    }

    showChildren = function() {
        wrangler:children()
    }

    subscriptions = function() {
      subs:established()
    }

    sensors = function() {
      subscriptions().filter(function(x) {x{"Tx_role"} == "sensor"})
    }

    rulesetURLS = [
      "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/twilio.sdk.krl",
      "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/subscriptions/temperature_store.krl",
      "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/subscriptions/wovyn_base.krl",
      "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/subscriptions/sensor_profile.krl",
      "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/subscriptions/wovyn_emitter.krl"
    ]

    getRIDs = function(){
      wrangler:installedRIDs()
    }

    all_temperatures = function() {
      sensors().map(function(v){
          value = v{"Tx"};
          answer = wrangler:picoQuery(value, "temperature_store", "temperatures", _host=v{"Tx_host"})
          answer
      }).values().reduce(function(a, b) {
          a.append(b)
      })
    }

  }

  rule setup_new_child{ 
    select when sensor:new_sensor
    pre {
        child_id = event:attrs{"child_id"}
        exists = (ent:children && ent:children >< (child_id).klog("exists: "))
        role = event:attrs{"role"}
      }
      if not exists then noop()
      fired {
        raise wrangler event "new_child_request"
          attributes { "name": child_id, "backgroundColor": "#fff44f", "child_id":child_id , "role": role}
      }
  }

  /*
  Add a profile ruleset to the sensor management pico that contains the 
  SMS notification number and a means of sending SMS messages to the 
  notification number. 
  */
  rule sendSMS {
    select when wovyn:sms_warning
        sdk:twilioSMS(event:attrs{"to"},
                        event:attrs{"from"},
                        event:attrs{"message"}) setting (response)
  }

  rule threshold_violation {
    select when sensor threshold_violation
    pre {
        message = event:attrs{"message"}
    }
    send_directive("send-message")

    fired {
        raise sensor event "forward_violation" attributes {
            "to": default_phone_number,
            "from":default_phone_number,
            "msg": message
        }
    }
  }

  rule notify_admin{
    select when sensor forward_violation
    pre{
      eci = event:attrs{"pico_eci"}
      args = {
        "to":event:attrs{"to"},
        "from": event:attrs{"from"},
        "msg":event:attrs{"msg"}
      }.klog("args: ")
    }
    wrangler:picoQuery(eci, "wovyn_base", "notifyAdmin", {})
  }

  rule child_already_exists {
    select when sensor:new_sensor
    pre {
      child_id = event:attrs{"child_id"}
      exists = ent:children && ent:children >< child_id
    }
    if exists then
      send_directive("child_ready", {"child_id":child_id, "data": ent:children})
  }

  rule store_new_child {
    select when wrangler new_child_created
    pre {
      child_eci = event:attrs{"eci"}.klog("eci: ")
      child_id = event:attrs{"name"}.klog("child name: ")
      child_role =  event:attrs{"role"}.klog("child role: ")
    }
    if child_id.klog("found child_id")
      then noop()
    fired {
      ent:children{[child_id,"eci"]} := child_eci
      ent:children{[child_id, "role"]} := child_role
    }
  }

  rule install_rulesets_in_child{
    select when wrangler child_initialized //manage_sensors install_rulesets_in_child
    foreach rulesetURLS setting (ruleURL)
    pre{
      eci = event:attrs{"eci"}.klog("given eci: ")
      name = event:attrs{"name"}.klog("given name: ")
      child_role =  ent:children{[name, "role"]}.klog("child role")
    }
    event:send(
      ruleset_event(ruleURL, eci, name, child_role)
    )
    fired {
      ent:children{[name, "eci"]} := eci on final
      raise sensor event "rulesets_installed"
          attributes {
              "eci": eci,
              "name": name,
              "role":child_role
          } on final
    }
  }

  rule rulesets_installed {
    select when sensor rulesets_installed
    pre {
      eci = event:attrs{"eci"}
      name = event:attrs{"name"}
      role = event:attrs{"role"}
    }
    if eci.klog("found sensor eci") then
      event:send({
        "eci": eci,
        "domain": "sensor", "type": "profile_updated",
        "attrs": {
          "name": name,
          "phone_number": default_phone_number, 
          "threshold": default_threshold,
          "location":default_location,
          "role": role
        }
      })
  }

  rule initialize_children_variable {
    select when children needs_initialization
    always {
      ent:children:= {}
      ent:subs := {}
    }
  }

  rule remove_child{
    select when sensor:unneeded_sensor
    pre {
      child_id = event:attrs{"child_id"}.klog("child_id: ")
      exists = (ent:children >< child_id).klog("exists: ")
      eci_to_delete = ent:children{[child_id, "eci"]}.klog("eci_to_delete: ")
    }
    if exists && eci_to_delete then
      send_directive("deleting_child", {"child_id":child_id})
    fired {
      raise wrangler event "child_deletion_request"
        attributes {"eci": eci_to_delete};
      clear ent:children{child_id}
    }
  }

  rule accept_wellKnown {
    select when child identify
      child_id re#(.+)#
      wellKnown_eci re#(.+)#
      setting(child_id,wellKnown_eci)
    fired {
      ent:children{[child_id,"wellKnown_eci"]} := wellKnown_eci.klog("child wellKnown_eci: ")
    }
  }

  rule introduce_foreign_sensor_to_manager {
    select when sensor add_sensor
    pre {
        wellKnown_eci = event:attrs{"wellKnown_eci"}.klog("well known eci")
        sensor_host = event:attrs{"Tx_host"}.klog("sensor host: ")
    }
    event:send({
        "eci": meta:eci, // manager eci
        "domain": "wrangler",
        "name": "subscription",
        "attrs": {
            "wellKnown_Tx": wellKnown_eci, // eci of the sensor
            "Rx_role": "management",
            "Tx_role": "sensor",
            "Tx_host": sensor_host, 
            "name": event:attrs{"name"},
            "channel_type": "subscription",
            "password":null
        }
    }.klog("raising event: ")) //, host= sensor_host) //<-- NOTE this only works with https
  }
  
  rule auto_accept { 
    select when wrangler inbound_pending_subscription_added
    pre {
      my_role = event:attrs{"Rx_role"}.klog("MY role: ") 
      their_role = event:attrs{"Tx_role"}.klog("THEIR role: ")
    }
    if my_role=="management" && their_role=="sensor" then noop()
    fired {
      raise wrangler event "pending_subscription_approval"
        attributes event:attrs
    } else {
      raise wrangler event "inbound_rejection"
        attributes event:attrs
    }
  }
}