ruleset temperature_store{
    meta {
      name "Temperature Store"
      description "Temperature sensor API"
      author "Joanna Hugo"
      provides temperatures, threshold_violations, inrange_temperatures
      shares temperatures, threshold_violations, inrange_temperatures
    }
    
    global{
        temperatures = function(){
            //returns the contents of the temperature entity variable
            ent:temps
        }

        threshold_violations = function(){
            // returns the contents of the threshold violation entity variable
            ent:violations
        }

        inrange_temperatures = function(){
            //returns all the temperatures in the temperature entity variable that aren't in the threshold violation entity variable. (
            //Note: I expect you to solve this without adding a rule that collects in-range temperatures)
            ent:temps.difference(ent:violations)
        }
    }

    /*
    You will need a rule in each sensor pico that listens for the event sent in (1), 
    and sends an event back to the originator of the event with the most recent temperature reading. 
    The sensor might also need to send its Rx channel back to the originator so that 
    the originator can differentiate what reports came from whom. 
    The originator is usually the sensor management pico, but don't make assumptions. 
    */
    rule gather{
      select when management:temp_report_request
      pre{
        orig_host = event:attrs{"originatorHOST"} || "http://localhost:3000"
        eci = event:attrs{"originatorID"}
        temp = ent:temps[ent:temps.length()-1]
      }
      event:send({
        "eci":eci,
        "domain": "sensor", "name": "temp_report",
          "attrs": {
            "report_correlation_number": event:attrs{"report_correlation_number"},
            "sensor_id": meta:eci,
            "temp": temp["temperature"]
          }
      })

    }


    rule intialization {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< ctx:rid
        if ent:temps.isnull()then noop()
        fired {
          ent:temps := []
          ent:violations := []
          ent:threshold := 100
        }
    }
     
    
    rule collect_temperatures{
      select when wovyn:new_temperature_reading 
      // stores the temperature and timestamp event attributes in an entity variable. 
      // The entity variable should contain all the temperatures that have been processed. 
      pre{
          passed_id = (event:attrs{"id"} || 234).klog("our passed in id: ")
          temp = event:attrs{"temperature"}.klog("temperature attr")
          time = (event:attrs{"timestamp"}||time:now()).klog("timestamp attr")
      }
      always{
          ent:temps := ent:temps.append({"temperature": temp, "timestamp": time }).klog("Adding temperature to temp entity var")
          raise api event "added_temp"
      }
    }

    rule collect_threshold_violations{
      select when wovyn:new_temperature_reading
      /*
      stores the violation temperature and a timestamp in a different entity variable that collects threshold violations.
      */
      pre{
        passed_id = (event:attrs{"id"} || 234).klog("our passed in id: ")
        temp = event:attrs{"temperature"}.klog("temperature attr")
        time = event:attrs{"timestamp"}.klog("timestamp attr")
      }

      if(temp > ent:threshold) then 
        send_directive("temp_violation", {"temp": temp})
      fired{
        ent:violations := ent:violations.append({"temperature": temp, "timestamp": time }).klog("Adding temperature to violations entity var")
        raise api event "temp_violations"
      }
      
    }

    rule profile_updated{
      select when sensor:successfully_updated
      pre{
          threshold = event:attrs{"threshold"}.klog("new threshold attribute -")
      }
      always{
          ent:threshold := threshold
      }
    }

    rule clear_temperatures{
        select when sensor:reading_reset
        //resets both entity variables
        always{
            ent:temps := []
            ent:violations := []
            ent:threshold := 100
            raise api event "reset"
        }
    }

  }