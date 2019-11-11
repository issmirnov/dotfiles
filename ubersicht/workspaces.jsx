import { run } from "uebersicht";

const yabai = "/usr/local/bin/yabai";
export const command = yabai + " -m query --spaces";
export const refreshFrequency = 500;

export const className = {
  top: 40,
  left: 40,
  color: '#ccc',
  fontFamily: 'Inconsolata',
  userSelect: "none",
};

function makeSwitcher(n) {
  function swtch(e) {
    let cmd = yabai + ' -m space --focus ' + n;
    run(cmd);
    console.log(cmd);
    return false;
  }
  return swtch;
}

function arrangeByDisp(spaces) {
  let displays = {};
  for (var i = 0; i < spaces.length; i++) {
    let displayList = displays[spaces[i].display];
    if (displayList) {
      displayList.push(spaces[i]);
    } else {
      displays[spaces[i].display] = [spaces[i]];
    }
  }
  return displays;
}

export const render = ({output, error}) => {
  if (error) {
    return (<div>Something went wrong: <strong>{String(error)}</strong></div>);
  }
  let spaces = JSON.parse(output);
  let displays = arrangeByDisp(spaces);
  let result = [];
  for (var i in displays) {
    let dispSpaces = [];
    for (var j = 0; j < displays[i].length; j++) {
      let elem =
        <span onClick={makeSwitcher(displays[i][j].index.toString())}>
          {displays[i][j].index.toString()}
        </span>;
      if (displays[i][j].visible) {
        dispSpaces.push(<strong style={{color: "#fff"}}>{elem}</strong>);
      } else {
        dispSpaces.push(elem);
      }
      if (j < displays[i].length - 1) {
        dispSpaces.push(" ");
      }
    }
    let style = {
      userSelect: "none",
      textAlign: "center",
      borderRadius: "0.4em",
      margin: "0.2em",
      display: "inline",
      background: "rgba(0,0,0,.65)",
      padding: "0.3em 0.5em 0.3em 0.5em",
    };
    result.push(
      <div style={style}>{dispSpaces}</div>);
  }

  return (<div style={{userSelect: "none"}}> {result} </div>);
}
