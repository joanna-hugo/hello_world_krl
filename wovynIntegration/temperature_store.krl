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

    rule intialization {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< ctx:rid
        if ent:temps.isnull()then noop()
        fired {
          ent:temps := []
          ent:violations := []
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
      select when wovyn:threshold_violations
      /*
      stores the violation temperature and a timestamp in a different entity variable that collects threshold violations.
      */
      pre{
        passed_id = (event:attrs{"id"} || 234).klog("our passed in id: ")
        temp = event:attrs{"temperature"}.klog("temperature attr")
        time = event:attrs{"timestamp"}.klog("timestamp attr")
      }

      always{
        ent:violations := ent:violations.append({"temperature": temp, "timestamp": time }).klog("Adding temperature to violations entity var")
        raise api event "temp_violations"
      }
    }

    rule clear_temperatures{
        select when sensor:reading_reset
        //resets both entity variables
        always{
            ent:temps := []
            ent:violations := []
            raise api event "reset"
        }
    }

  }