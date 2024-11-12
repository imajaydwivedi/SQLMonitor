import re

# https://www.ckhang.com/blog/2019/pyodbc-named-parameter-binding/
def bindParams(sql, params):
    bindingParams = []
    matches = re.findall(r'[:]\w+', sql)
    if len(matches) == 0:
        return sql, bindingParams

    for match in matches:
        key = match[1:]
        if key in params:
            bindingParams.append(params[key])
        else:
            raise ValueError('No value with key: ' + key)

    sql = re.sub(r'[:]\w+', r'?', sql)

    return sql, bindingParams

'''
params= {
    'first_name' : 'Khang',
    'last_name' : 'Tran',
    'home_address' : 'Itabashi',
    'office_address' : 'Chiyoda'
}

sql1 = 'INSERT INTO user_info (first_name, last_name, home_address) VALUES (:first_name, :last_name, :home_address)'
sql2 = 'INSERT INTO employee_info (first_name, last_name, office_address) VALUES (:first_name, :last_name, :office_address)'
sql, params1 = bindParams(sql1, params)
print(sql)
print(params1)
sql, params2 = bindParams(sql2, params)
print(sql)
print(params2)
'''