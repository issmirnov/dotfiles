import Desktop from './lib/Desktop/index.jsx';
import Error from './lib/Error/index.jsx';
import { leftSide } from './lib/style.jsx';
import parse from './lib/parse.jsx';

export const refreshFrequency = 100

export const command = '/usr/local/bin/yabai -m query --spaces'

export const render = ({output}) => {
  // console.log(`Left bar output: ${output}`);
  const data = parse(output);
  if (typeof data === 'undefined') {
    return (
      <div style={leftSide}>
        <Error msg="Error: unknown script output" side="left"/>
      </div>
    )
  }

  return (
    <div style={leftSide}>
        <Desktop output={data}/>
    </div>
  )
}

export default null
