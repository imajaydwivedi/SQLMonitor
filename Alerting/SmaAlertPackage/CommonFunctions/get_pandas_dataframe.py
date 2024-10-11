import pandas as pd
from pandas import DataFrame
# Video - https://www.youtube.com/watch?v=F6kmIpWWEdU
# Tutorials - https://www.datacamp.com/tutorial/pandas-tutorial-dataframe-python
# Docs - https://pandas.pydata.org/docs/reference/frame.html

def get_pandas_dataframe(pyodbc_query_resultset, index_col=''):
    if len(pyodbc_query_resultset) == 0:
        raise Exception(f"No data in passed resulset.")
    else:
        df_columns = [column[0] for column in pyodbc_query_resultset[0].cursor_description]
        #df_results = pd.DataFrame.from_records(pyodbc_query_resultset, columns=df_columns)

        if index_col != '':
            #df_results.set_index(index_col, inplace=True) # not working
            #print('setting specific index')
            index = df_columns.index(index_col)
            index_values = [row[index] for row in pyodbc_query_resultset]
            df_results = pd.DataFrame.from_records(pyodbc_query_resultset, index=index_values, columns=df_columns)
        else:
            df_results = pd.DataFrame.from_records(pyodbc_query_resultset, columns=df_columns)

    return df_results