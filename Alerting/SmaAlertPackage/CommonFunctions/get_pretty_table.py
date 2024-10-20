from prettytable import PrettyTable

def get_pretty_data_size(size:float,unit:str='mb',precision:int=2):
    unit = unit.lower()
    suffixes=['b', 'kb','mb','gb','tb']
    suffixIndex = suffixes.index(unit)
    while size > 1024 and suffixIndex < (len(suffixes)-1):
        suffixIndex += 1 #increment the index of the suffix
        size = size/1024.0 #apply the division
    return "%.*f %s"%(precision,size,suffixes[suffixIndex])

def get_pretty_table(pyodbc_query_resultset, return_pretty_data:bool=True):
    if len(pyodbc_query_resultset) == 0:
        raise Exception(f"No data in passed resulset.")
    else:
        pt_results = PrettyTable()
        col_names = [column[0] for column in pyodbc_query_resultset[0].cursor_description]
        pt_results.field_names = col_names
        pt_results.add_rows(pyodbc_query_resultset)

        if return_pretty_data:
            suffixes=['kb','mb','gb','tb']
            init = True
            for col in col_names:
                for unit in suffixes:
                    if col.endswith(f"_{unit}"):
                        if init:
                            pt_results.custom_format = { col: lambda field, value: get_pretty_data_size(float(value),field[-2:]) }
                            init = False
                        else:
                            pt_results.custom_format[col] = lambda field, value: get_pretty_data_size(float(value),field[-2:])

    return pt_results