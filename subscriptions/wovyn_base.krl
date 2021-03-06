ruleset wovyn_base{
    meta {
      name "Hello World"
      description "Wovyn temperature sensor integration"
      author "Joanna Hugo"
      use module org.twilio.sdk alias sdk
    }
     
    rule process_heartbeat{
      select when wovyn heartbeat genericThing re#(.*?)#
      pre{
        genericThing = event:attrs{"generifcThing"}.decode()
      }
       if(event:attrs{"genericThing"}) then 
          send_directive("ba-bum", {"genericThing": genericThing})
    
      fired{
        raise wovyn event "new_temperature_reading"
        attributes {
          "temperature" : event:attrs{"genericThing"}{"data"}{"temperature"}[0]{"temperatureF"},
          "timestamp"   : time:now()
        } 
      }    
    }

    rule find_high_temps{
      select when wovyn:new_temperature_reading
      pre{
        temperature_threshold = 100
        current = event:attrs{"temperature"}.klog("temperature attr")
      }
      if(event:attrs{"temperature"} > temperature_threshold) then 
        send_directive("temperature_violation", {"temp": event:attrs{"temperature"}, "timestamp":time:now()})
      fired{
        raise wovyn event "threshold_violation"
        attributes event:attrs
      }
    }

    rule threshold_notification{
      select when wovyn:threshold_violation
      always{
        raise wovyn event "sms_warning"
        attributes {
          "to":"+11111111111",
          "from":"+11111111111",
          "message":"save yourself!!"
        }
      }
    }

    rule sendSMS {
      select when wovyn:sms_warning
          sdk:twilioSMS(event:attrs{"to"},
                          event:attrs{"from"},
                          event:attrs{"message"}) setting (response)
    }
  }