command: "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep ' SSID' | cut -c 18-38"

refreshFrequency: 10000


render: (output) -> """
  <span><i class="fas fa-wifi"></i> #{output}</span>
"""

style: """
  height: 20px
  right: 37em
  background-color: #fb4934
  font: 12px Menlo
  padding-left: 1%
  padding-right: 1%

  span {
      position: relative
      top: 13%
  }
"""

