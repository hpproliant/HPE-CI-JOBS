import os
import sys
import gzip

html_start = """
<!DOCTYPE html>
    <html lang = "en-US">
    <head>
        <meta charset = 'utf-8'>
        <meta http-equiv = "X-UA-Compatible" content = "IE=edge">
        <meta name = "viewport" content = "width=device-width,maximum-scale=2">
        <!-- Begin Jekyll SEO tag v2.5.0 -->
        <title> HPE Proliant CI LOGS </title>
        <meta name = "generator" content = "Jekyll v3.8.5" />
        <meta property = "og:title" content = "HPE Proliant CI LOGS" />
        <meta property = "og:locale" content = "en_US" />
        <link rel = "canonical" href = "https://hpproliant.github.io/hpeproliant.github.io/" />
        <meta property = "og:url" content = "https://hpproliant.github.io/hpeproliant.github.io/" />
        <meta property = "og:site_name" content = "HPE Proliant CI LOGS" />
        <script type = "application/ld+json">
        {"@type": "WebSite", "headline": "HPE Proliant CI LOGS", "url": "https://hpproliant.github.io/hpeproliant.github.io/", "name": "HPE Proliant CI LOGS", "@context": "http://schema.org"} </script>
        <!-- End Jekyll SEO tag -->
    </head>
    <body>
     <!-- HEADER -->
        <div id = "header_wrap" class = "outer">
           <header class = "inner">
              <h1 id = "project_title"> HPE Proliant CI LOGS </h1>
              <h2 id = "project_tagline"> </h2>
            </header>
        </div>
        <!-- MAIN CONTENT -->
        <hr>
        <div id = "main_content_wrap" class = "outer">
            <style type = "text/css" media = "screen">
                .container {
                    margin: 0px auto
                    max-width: 80%
                    text-align: center
                 }
                h1 {
                    margin: 30px 0
                    font-size: 4em
                    line-height: 1
                    letter-spacing: -1px
                }
                table, td, th {
                    border: 0px solid black;
                }
            </style>
            <div class = "container"> """

html_end = """
            </div>
        </div>
        <!-- FOOTER  -->
        <hr>
        <div id="footer_wrap" class="outer">
            <footer class="inner">
                <p class="copyright">HPE Proliant CI LOGS maintained by iLO drivers team</p>
            </footer>
        </div>
    </body>
</html>
"""


def create_html(path):
    file_display = ""
    table_data = ""
    if os.path.isdir(path):
        cmd_list = os.listdir(path)
        if len(cmd_list) == 0 or path.split('/')[-1] == '.git':
            return
        table_start = "<table>\n"
        for i in cmd_list:
            new_path = os.path.join(path, i)
            if '.html' not in i:    
                if os.path.isdir(new_path):
                    table_start = table_start + \
                        "<tr><td><a href = 'https://hpproliant.github.io/hpeproliant.github.io/{}/{}.html'>{}</a></td></tr>\n".format(
                            new_path.split(sys.argv[1])[-1], i, i)
                else:
                    table_start = table_start + \
                        "<tr><td><a href = 'https://hpproliant.github.io/hpeproliant.github.io/{}.html'>{}</a></td></tr>\n".format(
                            new_path.split(sys.argv[1])[-1], i)
                
                create_html(new_path)
        table_data = table_start + "</table>\n"
    else:
        file_display = "<p><pre>\n"
        if '.gz' in path:
            with gzip.open(path, 'rb') as f:
                file_content = f.read()
        elif '.html' not in path:
            with open(path, 'r') as f:
                file_content = f.read()
        file_display = file_display + file_content + "</pre></p>"

    html_page = html_start + table_data + file_display + html_end
    if os.path.isdir(path):
        with open(os.path.join(path, (path.split('/')[-1] + '.html')), "w") as file:
            file.write(html_page)
    else:
        with open(path + '.html', "w") as file:
            file.write(html_page)


create_html(sys.argv[1])
