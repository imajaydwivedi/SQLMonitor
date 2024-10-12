from prettytable import PrettyTable

def get_pretty_dictionary(my_dict):
    pt = PrettyTable()
    pt.field_names = list(my_dict.keys())
    pt.add_row(list(my_dict.values()))

    return pt