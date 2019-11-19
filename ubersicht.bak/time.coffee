refreshFrequency: 30000
command: """
    date +"%H:%M"
"""

render: (output) -> """
   	<span><i class="fas fa-clock"></i> #{output}</span>
"""

style: """
  height: 20px
  right: 0%
  background-color: #8ec07c
  font: 12px Menlo
  padding-left: 1%
  padding-right: 1%

  span {
      position: relative
      top: 13%
  }
"""
