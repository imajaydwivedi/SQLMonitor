# HTML/URL to Image
    # https://stackoverflow.com/a/70910798/4449743

from html2image import Html2Image
hti = Html2Image()

# screenshot an URL
hti.screenshot(url='https://sqlmonitor.ajaydwivedi.com:3000/render/d-solo/distributed_live_dashboard_all_servers?panelId=844', save_as='distributed_live_dashboard_all_servers.png')