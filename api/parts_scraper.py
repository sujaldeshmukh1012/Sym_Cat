# import time
# from playwright.sync_api import sync_playwright

# def get_product_links_from_category(page, category_name, limit=5):
#     """Navigates to the product grid page."""
#     category_card_title = page.locator(f'[class*="shop-category-card__title"]:has-text("{category_name}")')
    
#     try:
#         category_card_title.first.click()
        
#         sub_cat_selector = '[class*="shop-category-card__title"]'
#         if page.locator(sub_cat_selector).first.is_visible(timeout=10000):
#             print("Sub-categories found, clicking the first one...")
#             page.locator(sub_cat_selector).first.click()

#         product_card_selector = '[class*="product-comparison__card-container"]'
#         print("Waiting for product cards to load...")
#         page.wait_for_selector(product_card_selector, timeout=20000)
        
#         return True
        
#     except Exception as e:
#         print(f"Failed to reach product grid for {category_name}: {e}")
#         return False

# def main():
#     with sync_playwright() as p:
#         browser = p.chromium.launch(headless=False, slow_mo=500)
#         context = browser.new_context(
#             viewport={'width': 1920, 'height': 1080},
#             user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
#         )
#         page = context.new_page()

#         try:
#             print("Navigating to Caterpillar...")
#             page.goto("https://parts.cat.com/en/catcorp/shop-all-categories", wait_until="load")

#             try:
#                 page.get_by_role("button", name="Accept All Cookies").click(timeout=5000)
#             except:
#                 pass

#             category_selector = '[class*="shop-category-card__title"]'
#             page.wait_for_selector(category_selector)
#             categories = [c.strip() for c in page.locator(category_selector).all_inner_texts() if c.strip()]
#             print("CATEGORIES: ", categories)
            
#             if categories:
#                 if get_product_links_from_category(page, categories[0]):
                    
#                     product_title_selector = '[class*="product-comparison__card-ellipsis"]'
                    
#                     final_parts_data = []

#                     for i in range(5):
#                         print(f"\nOpening product #{i+1}...")

#                         product_titles = page.locator(product_title_selector)
                        
#                         product_titles.nth(i).click()
                        
#                         try:
#                             page.wait_for_selector('[class*="cat-u-theme-typography-headline"]', timeout=15000)
                            
#                             serial = page.locator('[class*="cat-u-theme-typography-headline"]').first.inner_text().strip()
#                             name = page.locator('[class*="cat-u-theme-typography-label-lg"]').first.inner_text().strip()
#                             desc = page.locator('[class*="cat-u-theme-typography-body-sm"]').first.inner_text().strip()
                            
#                             item = {"serial": serial, "name": name, "description": desc}
#                             final_parts_data.append(item)
#                             print(f"Captured: {name} | {serial}")
                        
#                         except Exception as e:
#                             if "Access Denied" in page.content():
#                                 print("Blocked by Akamai. Stopping.")
#                                 break
#                             print(f"Could not extract details: {e}")

#                         print("Moving back to list...")
#                         page.go_back()
#                         page.wait_for_selector(product_title_selector, timeout=15000)
#                         time.sleep(2)
                    
#                     print("\n--- FINAL RESULTS ---")
#                     for data in final_parts_data:
#                         print(f"{data['serial']} - {data['name']}")

#         except Exception as e:
#             print(f"Error: {e}")
#         finally:
#             print("Closing browser...")
#             browser.close()

# if __name__ == "__main__":
#     main()


# import time
# from playwright.sync_api import sync_playwright

# def main():
#     with sync_playwright() as p:
#         browser = p.chromium.launch(headless=False, slow_mo=500)
#         context = browser.new_context(
#             viewport={'width': 1920, 'height': 1080},
#             user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
#         )
#         page = context.new_page()

#         try:
#             print("Navigating to Caterpillar...")
#             page.goto("https://parts.cat.com/en/catcorp/shop-all-categories", wait_until="load")

#             # 1. Get to the grid page
#             category_selector = '[class*="shop-category-card__title"]'
#             page.wait_for_selector(category_selector)
            
#             # Click the first category (Attachments)
#             page.locator(category_selector).first.click()
            
#             # Handle sub-category if it appears
#             sub_cat_selector = '[class*="shop-category-card__title"]'
#             if page.locator(sub_cat_selector).first.is_visible(timeout=10000):
#                 print("Clicking into sub-category...")
#                 page.locator(sub_cat_selector).first.click()

#             # 2. Wait for the Product Grid to load
#             product_card_selector = '[class*="product-comparison__card-container"]'
#             print("Waiting for products to appear on grid...")
#             page.wait_for_selector(product_card_selector, timeout=20000)

#             # 3. SCRAPE DIRECTLY FROM THE GRID
#             # We target each card and pull the text from the specific classes you found
#             cards = page.locator(product_card_selector)
#             count = cards.count()
#             print(f"Found {count} product cards on this page.")

#             final_data = []
            
#             # Use the classes you identified for the grid view
#             for i in range(min(count, 10)): # Let's look at the first 10
#                 card = cards.nth(i)
                
#                 # Serial is usually the headline class in the card
#                 serial = card.locator('[class*="cat-u-theme-typography-headline"]').inner_text().strip()
                
#                 # Name is the label class you found
#                 name = card.locator('[class*="cat-u-theme-typography-label-lg"]').inner_text().strip()
                
#                 # Description might be truncated on the grid, but let's grab what's there
#                 desc = card.locator('[class*="cat-u-theme-typography-body-sm"]').inner_text().strip()

#                 final_data.append({"serial": serial, "name": name, "desc": desc})
#                 print(f"✅ Extracted from Grid: {serial} | {name}")

#             print("\n--- RESULTS FROM GRID DOM ---")
#             for item in final_data:
#                 print(f"Part: {item['name']} | ID: {item['serial']}")

#         except Exception as e:
#             print(f"Error: {e}")
#         finally:
#             print("Closing browser...")
#             time.sleep(5)
#             browser.close()

# if __name__ == "__main__":
#     main()