import { container, arrow, content } from './style.jsx';

// Set time to RED if past bedtime.
const updateStyling = (time) => {
  let contentStyle = JSON.parse(JSON.stringify(content));
  let arrowStyle = JSON.parse(JSON.stringify(arrow));
  let hour = time.split(":")[0]
  let minute = time.split(":")[1]
  contentStyle.color = 'rgba(76, 86, 106, 1)';
  if (hour  < 4 || (hour == 23 && minute > 30)) {
    contentStyle.fontWeight = 'bold';
    contentStyle.background = 'rgba(191, 97, 106, 1)';
    arrowStyle.borderRight = '10px solid rgba(191, 97, 106, 1)';
  }
  return { contentStyle, arrowStyle };
}

const render = ({output}) => {
  if (typeof output === 'undefined') return null;
  const { contentStyle, arrowStyle } = updateStyling(output.time);
  return (
    <div style={container}>
      <div style={arrowStyle}/>
      <div style={contentStyle}>
        <i class="fas fa-calendar-alt"/>&nbsp;{output.date}&nbsp;
        <i class="fas fa-clock"/>&nbsp;{output.time}
      </div>
    </div>
  )
}

export default render
