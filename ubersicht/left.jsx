import Desktop from './lib/Desktop/index.jsx';
import Error from './lib/Error/index.jsx';
import { leftSide } from './lib/style.jsx';
import parse from './lib/parse.jsx';

export const refreshFrequency = 10000

export const command = '/usr/local/bin/yabai -m query --spaces'

export const render = ({output}) => {
  console.log(`Left bar output: ${output}`);
  const data = parse(output);
  if (typeof data === 'undefined') {
    return (
      <div style={leftSide}>
        <Error msg="Error: unknown script output" side="left"/>
      </div>
    )
  }

  // dead code, this doesn't happen.
  if (typeof data.error !== 'undefined') {
    return (
      <div style={leftSide}>
        <Error msg={`Error: ${data.error}`} side="left"/>
      </div>
    )
  }

  console.log(`left data: ${data}`)
  // react - farm out to child.
  return (
    <div style={leftSide}>
        <Desktop output={data}/>
    </div>
  )
}

export default null
