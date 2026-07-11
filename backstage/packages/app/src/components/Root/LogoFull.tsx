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

const LogoFull = () => {
  const classes = useStyles();
  return (
    <svg className={classes.svg} viewBox="0 0 220 30" xmlns="http://www.w3.org/2000/svg">
      <text x="0" y="22" className={classes.text}>
        jenkins-2026
      </text>
    </svg>
  );
};

export default LogoFull;
