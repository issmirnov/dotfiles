refreshFrequency: 30000
command: "ESC=`printf \"\e\"`; ps -A -o %cpu | awk '{s+=$1} END {printf(\"%.2f\",s/8);}'"

render: (output) -> """
   	<span><i class="fas fa-tachometer-alt"></i> #{output}%</span>
"""

style: """
  height: 20px
  right: 29em
  background-color: #d3869b
  font: 12px Menlo
  padding-left: 1%
  padding-right: 1%

  span {
      position: relative
      top: 13%
  }

"""
