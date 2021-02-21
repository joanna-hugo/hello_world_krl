ruleset sensor_profile{
    meta {
        name "Temperature Store"
        description "Temperature sensor API"
        author "Joanna Hugo"
        use module org.twilio.sdk alias sdk
        with
        authToken = meta:rulesetConfig{"authToken"}
        accountSID = meta:rulesetConfig{"accountSID"}
        provides location, name, threshold, phone_number
        shares location, name, threshold, phone_number
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
    }

    rule profile_updated{
        select when sensor:profile_updated
        pre{
            location = event:attrs{"location"} || ent:location
            name =  event:attrs{"name"} || ent:name
            threshold = event:attrs{"threshold"} || ent:threshold
            number = event:attrs{"phone_number"} || ent:number
        }
        always{
            ent:location := location.klog("new location ")
            ent:name := name.klog("new name ")
            ent:threshold := threshold.klog("new threshold")
            ent:number := number.klog("new number")
            raise sensor event "successfully_updated" 
                attributes{
                    "location": ent:location,
                    "name": ent:name,
                    "number": ent:number,
                    "threshold":ent:threshold
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
}