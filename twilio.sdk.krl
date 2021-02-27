ruleset org.twilio.sdk {
    meta {
      name "Twilio SDK"
      author "Joanna HUgo"
      description "An SDK for Twilio"
      configure using
        authToken = ""
        accountSID = ""
      provides twilioSMS, messages
    }
    global {
      base_url = "@api.twilio.com/2010-04-01/Accounts/"
      
      twilioSMS = defaction(to, from, message) {
        base_url = <<https://#{accountSID}:#{authToken}#{base_url}#{accountSID}/>>
        http:post(base_url + "Messages.json", form = {
                 "From":from,
                 "To":to,
                 "Body":message
             })
      }

     messages = function(to, from, pagesize ){
      base_url = <<https://#{accountSID}:#{authToken}#{base_url}#{accountSID}/>>
      url = base_url + "Messages.json"

      queryMap = {
        "To":to,
        "From": from,
        "PageSize": pagesize.as("Number")
      }.filter()
      result = http:get(url, qs = queryMap){"content"}.decode()
      result // this is the return value
      }
    }
  }
  