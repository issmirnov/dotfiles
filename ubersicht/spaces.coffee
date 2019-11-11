command: "/usr/local/bin/yabai -m query --spaces"

refreshFrequency: 100

removeDuplicates: (ar) ->
  if ar.length == 0
    return []
  res = {}
  res[ar[key]] = ar[key] for key in [0..ar.length-1]
  value for key, value of res

generateIcons: (spaces) ->
  displays = @removeDuplicates((space['display'] for space in spaces))
  iconString = ""
  for display in displays
    for space in spaces when space['display'] == display
      # iconString += "<li onclick=@run(\"say hi\") id=\"desktop#{space['index']}\">#{space['index']}</li>"
      iconString += "<li id=\"desktop#{space['index']}\">#{space['index']}</li>"
    if display < displays.length
      iconString += "<li>—</li>"
  return iconString

render: (output) ->
  spaces = JSON.parse(output)
  htmlString = """
    <div class="spaces-container" data-count="#{spaces.length}">
      <ul>
        #{@generateIcons(spaces)}
      </ul>
    </div>
  """

# handleClick: (elem) ->
#   console.log("handle click")
#   console.log(elem)
#   @run("say click")

afterRender: (domEl) ->
  console.log("after render")
  #instanceMethods = (v for k, v of domEl when typeof v is "function")
  #console.log(domEl)
  #console.log(instanceMethods)
  # $(":root").find("li").each() - in console.
  # $(":root").find("li")[1].click()
  # @run("say hi")
  #console.log($(domEl).find('li'))
  # $(domEl).on 'click', => @run("say hi")
  $(domEl).find('li').on 'click', (event) =>
    # console.log(event)
    # console.log(event.target.innerText)
    # console.log("click")
    @run("say " + event.target.innerText)
    @run("/usr/local/bin/yabai -m space --focus " + event.target.innerText)

    # works!
    # console.log(this)
    # @handleClick(this)

  # OLD
  # $(domEl).find('li').on 'click', => @run("say hi @this")
  # $(domEl).find('.li').on 'click', => @run("say hi" + this.val())

style: """
  user-select: none
  position: relative
  margin-top: 7px
  margin-left: 10px
  font: 14px "HelveticaNeue-Light", "Helvetica Neue Light", "Helvetica Neue", Helvetica, Arial, "Lucida Grande", sans-serif
  color: #aaa
  font-weight: 700
  z-index: 100

  ul
    list-style: none
    margin: 0 0 0 1em
    padding: 0

  li
    display: inline-block
    text-align: center
    width: 1em
    margin: 0 0.5em

  li.visible
    color: #ededed
    border-bottom: 2px solid #ededed
"""

update: (output, domEl) ->
  spaces = JSON.parse(output)
  if ($(domEl).find('.spaces-container').attr('data-count') != spaces.length.toString())
    $(domEl).find('.spaces-container').attr('data-count', "#{spaces.length}")
    $(domEl).find('ul').html(@generateIcons(spaces))
  else
    $(domEl).find('li.visible').removeClass('visible')
  for space in spaces when space['visible'] == 1
    $(domEl).find("li#desktop#{space['index']}").addClass('visible')
