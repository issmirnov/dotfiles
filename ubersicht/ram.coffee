refreshFrequency: 30000
command: "ESC=`printf \"\e\"`; ps -A -o %mem | awk '{s+=$1} END {printf(s)}'"

render: (output) -> """
   	<span><i class="fas fa-memory"></i> #{output}%</span>
"""

style: """
  height: 20px
  right: 20em
  background-color: #b8bb26
  font: 12px Menlo
  padding-left: 1%
  padding-right: 1%

  span {
      position: relative
      top: 13%
  }
"""

