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
  }

  global{
      hello_world = function(){
          "hello world"
      }

      sensors = function(){
          ent:children
      }

      ruleset_event = function(URL, eci, child_id){
        { "eci": eci, 
            "eid": "install-ruleset", // can be anything, used for correlation
            "domain": "wrangler", "type": "install_ruleset_request",
            "attrs": {
              "url": URL,
              "config": {
                "authToken": "#{{authToken}}",
                "accountSID" : accountSID
              },
              "child_id": child_id
            }
          }.klog("ruleset event returning: ")
      }

      showChildren = function() {
          wrangler:children()
      }

      rulesetURLS = [
        "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/wovynIntegration/temperature_store.krl",
        "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/wovynIntegration/wovyn_base.krl",
        "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/wovynIntegration/sensor_profile.krl",
        "file:///Users/user/Documents/winter21/distributed/krl/hello_world_krl/wovynIntegration/wovyn_emitter.krl"
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
      ent:children{child_id} := child_eci
    }
  }

  rule trigger_install_ruleset_in_child {
    select when wrangler new_child_created
    pre {
      child_eci = event:attrs{"eci"}.klog("the child eci: ")
      child_id = event:attrs{"child_id"}.klog("child id/name ")
    }
    if child_id.klog("found child_id")
    then 
      event:send({
          "domain"  : "manage_sensors",
          "type"    : "install_rulesets_in_child",
          "eci"     : child_eci,
          "name"    : child_id
        }
      )
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

  rule initialize_state {
    select when wrangler ruleset_installed
      send_directive("RULESET INSTALLED, HALLELUJAH")
  }

  rule initialize_children_variable {
    select when children needs_initialization
    always {
      ent:children:= {}
    }
  }

  rule remove_child{
    select when sensor:unneeded_sensor
    pre {
      child_id = event:attrs{"child_id"}.klog("child_id: ")
      exists = (ent:children >< child_id).klog("exists: ")
      eci_to_delete = ent:children{child_id}.klog("eci_to_delete: ")
    }
    if exists && eci_to_delete then
      send_directive("deleting_section", {"child_id":child_id})
    fired {
      raise wrangler event "child_deletion_request"
        attributes {"eci": eci_to_delete};
      clear ent:children{child_id}
    }
  }

  rule set_child_profile{
    select when wrangler ruleset_installed
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
    
  // rule get_temps{
  //   select when sensors:get_temps
  //   pre{
  //     children_ecis = ent:children.values().klog("ecis: ")
  //   }
  //   foreach (children_ecis) setting (eci)
  //     send_directive("temperatures": http:get("http://localhost:3000/sky/cloud/" + eci + "/temperatures"))
  // }
}