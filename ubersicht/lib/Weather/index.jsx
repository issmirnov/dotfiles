import { container, arrow, content } from './style.jsx';

const render = ({output}) => {
  if (typeof output === 'undefined') return null;
  return (
    <div style={container}>
      <div style={arrow}/>
      <div style={content}>
       {output.forecast}
      </div>
    </div>
  )
}

export default render
