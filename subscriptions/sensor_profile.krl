ruleset sensor_profile{
    meta {
        name "Temperature Store"
        description "Temperature sensor API"
        author "Joanna Hugo"
        use module org.twilio.sdk alias sdk
        use module io.picolabs.wrangler alias wrangler 
        use module io.picolabs.subscription alias subs
        provides location, name, threshold, phone_number
        shares location, name, threshold, phone_number, wellKnown_Rx, student_eci, role
    }
        
    global{
        location = function(){
            ent:location
        }
        name = function(){
            ent:name
        }
        threshold = function(){
            ent:threshold
        }
        phone_number = function(){
            ent:number
        }
        wellKnown_Rx = function(){
          ent:wellKnown_Rx
        }
        student_eci = function(){
          ent:student_eci
        }
        role = function(){
          ent:role
        }
    }

    rule profile_updated{
        select when sensor:profile_updated
        pre{
            location = event:attrs{"location"} || ent:location
            name =  event:attrs{"name"} || ent:name
            threshold = event:attrs{"threshold"} || ent:threshold
            number = event:attrs{"phone_number"} || ent:number
            role = event:attrs{"role"} || ent:role
        }
        always{
          ent:location := location.klog("new location ")
          ent:name := name.klog("new name ")
          ent:threshold := threshold.klog("new threshold")
          ent:number := number.klog("new number")
          ent:role := role
          raise sensor event "successfully_updated" 
              attributes{
                  "location": ent:location,
                  "name": ent:name,
                  "number": ent:number,
                  "threshold":ent:threshold,
                  "role": ent:role
              } 
        }
    }

    rule threshold_updated{
        select when sensor:successfully_updated
        pre{
            threshold = event:attrs{"threshold"}.klog("new threshold attribute -")
            number = event:attrs{"number"}.klog("sms bymber to update - ")
        }
        always{
            ent:threshold := threshold

            raise wovyn event "sms_warning"
            attributes {
              "to":number,
              "from":"+11111111",
              "message":"profile updated"
            }
        }
    }

    rule pico_ruleset_added {
        select when wrangler ruleset_installed
          //where event:attrs{"rids"} >< meta:rid
        pre {
          child_id = event:attrs{"child_id"}.klog("child id")
          parent_eci = wrangler:parent_eci()
          wellKnown_eci = subs:wellKnown_Rx(){"id"}
          role = event:attrs{"child_role"}
        }
        event:send({"eci":parent_eci,
          "domain": "child", "type": "identify",
          "attrs": {
            "child_id": child_id,
            "wellKnown_eci": wellKnown_eci
          }
        })
        always {
          ent:child_id := child_id
          ent:role := role
        }
    }

    rule capture_initial_state {
      select when wrangler ruleset_installed
        // where event:attr("rids") >< meta:rid
      if ent:student_eci.isnull() then
        wrangler:createChannel(["allow-all", event:attrs{"child_id"}]) setting(channel)
      fired {
        ent:name := event:attrs{"child_id"}.klog("name")
        ent:wellKnown_Rx := wrangler:parent_eci().klog("wellKnown_RX AKA parent ECI: ")//NOTE this works but is not standard
        ent:student_eci := channel{"id"}.klog("student eci")
        ent:rids := event:attrs{"rids"}.klog("rids: ")
        raise student event "new_subscription_request" // TODO student --> sensor or child
      }
    }
 

    rule intialization {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< ctx:rid
        if not ent:threshold.isnull()
            then noop()
        fired {
            ent:location := "Office"
            ent:name := "for school"
            ent:threshold := 100
            ent:number := "+13854843283"
        }
    }

    rule make_a_subscription { 
      select when student new_subscription_request
      event:send({"eci":ent:wellKnown_Rx.klog("wellKnown_Rx"),
        "domain":"wrangler", "name":"subscription",
        "attrs": {
          "wellKnown_Tx":subs:wellKnown_Rx(){"id"},
          "Rx_role":"management", "Tx_role":ent:role, 
          "name":ent:name+"-registration", "channel_type":"subscription"
        }
      })
    }

    rule auto_accept {
      select when wrangler inbound_pending_subscription_added
      pre {
        my_role = event:attr("Rx_role").klog("my role: ")
        their_role = event:attr("Tx_role").klog("their role: ")
      }
      if my_role=="sensor" && their_role=="management" then noop()
      fired {
        raise wrangler event "pending_subscription_approval"
          attributes event:attrs
        ent:subscriptionTx := event:attr("Tx")
      } else {
        raise wrangler event "inbound_rejection"
          attributes event:attrs
      }
    }
}



