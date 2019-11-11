command: "date +\"%a, %b %d %H:%M\""

refreshFrequency: 100

# date: () ->
#   return @run("date")

render: (output) ->
  htmlString = """
        #{output}
  """


style: """
  user-select: none
  font: 14px "Source Code Pro" "HelveticaNeue-Light", "Helvetica Neue Light", "Helvetica Neue", Helvetica, Arial, "Lucida Grande", sans-serif
  color: #aaa
  z-index: 1
  top: 7px
  right: 24px
  font-weight: 700
  display: inline-block
  text-align: right
"""
