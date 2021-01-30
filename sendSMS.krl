ruleset sendSMS_rule {
  meta {
    use module org.twilio.sdk alias sdk
      with
        authToken = meta:rulesetConfig{"authToken"}
        accountSID = meta:rulesetConfig{"accountSID"}
    shares getMessages
  }
  global{
    getMessages = function(){
      sdk:messages()
    }
  }

  rule sendSMS {
    select when test new_message
        sdk:twilioSMS(event:attrs{"to"},
                        event:attrs{"from"},
                        event:attrs{"message"}) setting (response)
  }

  rule getMessages{
    select when test get_message
    pre{
      test = "prelude".klog("in rule ")
      result = sdk:messages(event:attrs{"to"}, 
                              event:attrs{"from"})
      messages = result.decode().get(["messages"])                      
    } 
    send_directive({"messages":messages})

    fired {
      raise getMessages event "Got Messages" attributes event:attrs
    }
}

}