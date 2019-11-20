import DateTime from './lib/DateTime/index.jsx';
import Battery from './lib/Battery/index.jsx';
import Cpu from './lib/Cpu/index.jsx';
import Memory from './lib/Memory/index.jsx';
import Wifi from './lib/Wifi/index.jsx';
import Weather from './lib/Weather/index.jsx';
import Error from './lib/Error/index.jsx';
import { rightSide } from './lib/style.jsx';
import parse from './lib/parse.jsx';

export const refreshFrequency = 100

export const command = './status-right.sh'

export const render = ({output}) => {
  // console.log(`Right bar output: ${output}`);
  const data = parse(output);
  if (typeof data === 'undefined') {
    return (
      <div style={rightSide}>
        <Error msg="Error: unknown script output" side="right"/>
      </div>
    )
  }
  return (
    <div style={rightSide}>
	<Wifi output={data.wifi}/>
	{/* <Memory output={data.memory}/> */}
	<Battery output={data.battery}/>
	<Cpu output={data.cpu}/>
	<Weather output={data.weather}/>
	<DateTime output={data.datetime}/>
    </div>
  )
}

export default null
