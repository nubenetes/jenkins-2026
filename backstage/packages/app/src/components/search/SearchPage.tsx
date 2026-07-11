import React from 'react';
import { makeStyles, Grid, Paper } from '@material-ui/core';
import { CatalogSearchResultListItem } from '@backstage/plugin-catalog';
import { TechDocsSearchResultListItem } from '@backstage/plugin-techdocs';
import { Content, Header, Page } from '@backstage/core-components';
import {
  SearchBar,
  SearchResult,
  SearchPagination,
  SearchResultPager,
} from '@backstage/plugin-search-react';

const useStyles = makeStyles(theme => ({
  bar: { padding: theme.spacing(1, 0) },
}));

const SearchPage = () => {
  const classes = useStyles();
  return (
    <Page themeId="home">
      <Header title="Search" />
      <Content>
        <Grid container direction="row">
          <Grid item xs={12}>
            <Paper className={classes.bar}>
              <SearchBar />
            </Paper>
          </Grid>
          <Grid item xs={12}>
            <SearchPagination />
            <SearchResult>
              <CatalogSearchResultListItem />
              <TechDocsSearchResultListItem />
            </SearchResult>
            <SearchResultPager />
          </Grid>
        </Grid>
      </Content>
    </Page>
  );
};

export const searchPage = <SearchPage />;
