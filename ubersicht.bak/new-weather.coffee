latitude = "yourlat"
longitude = "yourlong"
apiKey = "yourkeyhere"

# command: "curl -s 'https://api.forecast.io/forecast/#{apiKey}/#{latitude},#{longitude}?exclude=minutely,hourly,flags'"
command: "curl --silent 'wttr.in/?mQ0&format=%c%t&period=60'"

refreshFrequency: '15m'

style: """
  height: 20px
  right: 72em
  font: 12px Menlo
  background-color: #fe8019
  padding-left: 1%
  padding-right: 1%
  # margin-top: -1px
  span {
      position: relative
      top: 13%
  }
"""

render: -> """
 <span><span class="conditions"></span></span>
"""

update: (output, domEl) ->
  $(domEl).find('.conditions').html(output)
