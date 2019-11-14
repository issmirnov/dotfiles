import { bar } from './lib/style.jsx';

export const refreshFrequency = 1000000

export const render = ({output}) => {
  return (
    <div style={bar}>
      <link href="/common/css/all.css" rel="stylesheet"/>
    </div>
  )
}

export default null
