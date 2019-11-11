command: "/usr/local/bin/yabai -m query --windows --space | /usr/local/bin/jq -r '.[] | select(.focused==1) | [.app] | @tsv'"
# command: "/usr/local/bin/yabai -m query --windows --space | /usr/local/bin/jq -r '.[] | select(.focused==1) | [.app,.title] | @tsv'"

refreshFrequency: 100

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
  left: 20px
  right: 20px
  display: inline-block
  margin: 0 auto;
  font-weight: 700
  text-align: center
"""
