command: "curl --silent 'wttr.in/?mQ0&format=%c%t&period=60'"

refreshFrequency: 600000 # 10 minutes


render: (output) ->
  htmlString = """
        #{output}
  """


style: """
  user-select: none
  font: 14px "Source Code Pro" "HelveticaNeue-Light", "Helvetica Neue Light", "Helvetica Neue", Helvetica, Arial, "Lucida Grande", sans-serif
  color: #aaa
  z-index: 1
  top: 2px
  right: 210px
  font-weight: 700
  display: inline-block
  text-align: right
"""
