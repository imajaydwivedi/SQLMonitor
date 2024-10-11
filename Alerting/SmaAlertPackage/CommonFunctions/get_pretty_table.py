from prettytable import PrettyTable

def get_pretty_table(pyodbc_query_resultset):
    if len(pyodbc_query_resultset) == 0:
        raise Exception(f"No data in passed resulset.")
    else:
        pt_results = PrettyTable()
        pt_results.field_names = [column[0] for column in pyodbc_query_resultset[0].cursor_description]
        pt_results.add_rows(pyodbc_query_resultset)

    return pt_results