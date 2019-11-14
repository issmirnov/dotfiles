import { container, arrow, content } from './style.jsx';

const render = ({output}) => {
  if (typeof output === 'undefined') return null;
	const usedMemory = 100 - output.free;
  return (
    <div style={container}>
      <div style={arrow}/>
      <div style={content}>
        <i class="fas fa-memory"/>&nbsp;{usedMemory}%
      </div>
    </div>
  )
}

export default render
