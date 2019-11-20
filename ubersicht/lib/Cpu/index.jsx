import { container, arrow, content } from './style.jsx';

const updateStyling = (cpuUsage) => {
  let contentStyle = JSON.parse(JSON.stringify(content));
  let arrowStyle = JSON.parse(JSON.stringify(arrow));
  contentStyle.color = 'rgba(76, 86, 106, 1)';

  // white: (235, 239, 243, 1)
  // yellow: (235, 203, 139, 1)
  // orange: (208, 135, 113, 1)
  // green: (163, 189, 140, 1)
  // red: (191, 97, 106, 1)
  console.log(`cpu usage: ${cpuUsage}`)
  // let derp = 112 < 20;
  let derp = 60 <= 112;
  console.log(`derp: ${derp}`)

  if (cpuUsage < 20) { // white
    contentStyle.background = 'rgba(235, 239, 243, 1)';
    arrowStyle.borderRight = '10px solid rgba(235, 239, 243, 1)';
  } else if (20 <= cpuUsage < 40) { // green
    contentStyle.background = 'rgba(163, 189, 140, 1)';
    arrowStyle.borderRight = '10px solid rgba(163, 189, 140, 1)';
  } else if (40 <= cpuUsage < 60) { // yellow
    contentStyle.background = 'rgba(235, 203, 139, 1)';
    arrowStyle.borderRight = '10px solid rgba(235, 203, 139, 1)';
  } else if (60 <= cpuUsage) { // red
    contentStyle.background = 'rgba(191, 97, 106, 1)';
    arrowStyle.borderRight = '10px solid rgba(191, 97, 106, 1)';
  }
  return { contentStyle, arrowStyle };
}

const render = ({output}) => {
  if (typeof output === 'undefined') return null;
  const { contentStyle, arrowStyle } = updateStyling(output.loadAverage);
  return (
    <div style={container}>
      <div style={arrowStyle}/>
      <div style={contentStyle}>
        <i class="fas fa-microchip"/>&nbsp;{output.loadAverage}%
      </div>
    </div>
  )
}

export default render
