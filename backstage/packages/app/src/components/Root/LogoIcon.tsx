import React from 'react';
import { makeStyles } from '@material-ui/core';

const useStyles = makeStyles({
  svg: { width: 'auto', height: 28 },
  text: {
    fill: '#7df3e1',
    fontFamily: 'Helvetica, Arial, sans-serif',
    fontSize: 20,
    fontWeight: 700,
  },
});

const LogoIcon = () => {
  const classes = useStyles();
  return (
    <svg className={classes.svg} viewBox="0 0 30 30" xmlns="http://www.w3.org/2000/svg">
      <text x="2" y="22" className={classes.text}>
        j2
      </text>
    </svg>
  );
};

export default LogoIcon;
