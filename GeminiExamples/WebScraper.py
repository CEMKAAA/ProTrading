from bs4 import BeautifulSoup
import requests

headers = {
     "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36"
}

def fetch_website_content(url):
     """
          Urlsi verilen websitesindeki başlıkları ve içerikleri çek
          içeriği 2000 karakter ile sınırla
     """
     
     response = requests.get(url, headers = headers)
     soup = BeautifulSoup(response.content, "html.parser")
     title = soup.title.string if soup.title else "Başlık Bulunamadı"
     
     if soup.body:
          for irrelevant in soup.body(["script", "style", "img", "input"]):
               irrelevant.decompose()
               
          text = soup.body.get_text(separator="\n", strip=True)
          # Limit to 2000 characters
          text = text[:2000] if len(text) > 2000 else text
          
          return (title + "\n\n" + text)[:2_000]
     else:
          return {
               'title': title,
               'content': "İçerik bulunamadı",
               'url': url
          }
          
def fetch_website_links(url):
     """
          urlsi verilen websitesindeki linkleri çek
     """
     
     response = requests.get(url, headers=headers)
     soup = BeautifulSoup(response.content, "html.parser")
     links = [link.get("href") for link in soup.find_all("a", href=True)]
     return [link for link in links if link and link.startswith("http")]
     
     