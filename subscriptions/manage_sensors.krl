ruleset manage_sensors{
  meta {
    name "Managae Sensors"
    description "Manages several childs, each representing a sensor"
    author "Joanna Hugo"
    shares sensors, showChildren, getRIDs//accessible from GUI
    provides ruleset_event //internal
    configure using
      authToken = ""
      accountSID = ""
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias subs
  }

  global{

    sensors = function(){
      ent:children
    }  

    ruleset_event = function(URL, eci, child_id){
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
          "child_id": child_id
        }
      }.klog("ruleset event returning: ")
    }

    showChildren = function() {
        wrangler:children()
    }

    subscriptions = function(){
      ent:subs
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

  }

  rule setup_new_child{ 
    select when sensor:new_sensor
    pre {
        child_id = event:attrs{"child_id"}
        exists = (ent:children && ent:children >< (child_id).klog("exists: "))
        
      }
      if not exists then noop()
      fired {
        raise wrangler event "new_child_request"
          attributes { "name": child_id, "backgroundColor": "#fff44f", "child_id":child_id }
      }
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
    }
    if child_id.klog("found child_id")
      then noop()
    fired {
      ent:children{[child_id,"eci"]} := child_eci
    }
  }

  rule install_rulesets_in_child{
    select when wrangler child_initialized //manage_sensors install_rulesets_in_child
    foreach rulesetURLS setting (ruleURL)
    pre{
      eci = event:attrs{"eci"}.klog("given eci: ")
      name = event:attrs{"name"}.klog("given name: ")
    }
    event:send(
      ruleset_event(ruleURL, eci, name)
    )
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

  rule set_child_profile{
    select when wrangler install_ruleset_request where event:attrs{"url"} == rulesetURLS[3]
    pre{
      url = "http://localhost:3000/sky/event/" + event:attrs{"eci"} + "/sensor/profile_updated"
    }
    http:post(url, form = {
      "location":"home",
      "threshold":100,
      "name":event:attrs{"name"}.klog("child profile name: "),
      "phone_number":"18001234567"
    })
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
        wellKnown_eci = event:attrs{"wellKnown_eci"}
        Tx_host = event:attrs{"Tx_host"}
    }
    event:send({
        "eci": wellKnown_eci,
        "domain": "wrangler",
        "name": "subscription",
        "attrs": {
            "wellKnown_Tx": subs:wellKnown_Rx(){"id"},
            "Rx_role": "sensor",
            "Tx_role": "management",
            "Tx_host": Tx_host,
            "name": event:attrs{"name"}+"-management",
            "channel_type": "subscription"
        }
    })
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
      ent:subscriptionTx := event:attrs{"Tx"}.klog("fired wrangler: inbound_pending_subscription_added event")
    } else {
      raise wrangler event "inbound_rejection"
        attributes event:attrs
    }
  }
}