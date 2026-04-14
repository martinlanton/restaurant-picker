import Foundation

// MARK: - Data Structures

/// A named group of cuisine labels, used as a sub-group within a region.
///
/// For a **country** entry, this holds the regional cuisines of that country.
/// For a **continent** entry, each group represents one of its member countries.
struct CuisineGroup: Identifiable {
    let id = UUID()
    /// Display name of the group (e.g. "Japanese", "Italian").
    let name: String
    /// Leaf-level cuisine labels that belong to this group.
    /// These match keys in `RestaurantSearchService.cuisineQueries`.
    let cuisines: [String]
}

/// A top-level entry in the filter hierarchy — either a continent or a country.
///
/// - A **continent** has multiple `CuisineGroup` children (one per country).
///   Its leaves are ALL cuisines across all its groups.
/// - A **country** has a single `CuisineGroup` holding its regional cuisines.
///   If `groups` is empty the country is a leaf toggle with no sub-cuisines.
struct CuisineRegion: Identifiable {
    let id = UUID()
    /// Display name shown at the top level (e.g. "🌏 Asia", "🇯🇵 Japanese").
    let name: String
    /// Whether this entry is a continent (`true`) or a country/group (`false`).
    let isContinent: Bool
    /// Sub-groups. Continents have one group per country; countries have one group.
    let groups: [CuisineGroup]

    /// Flat list of every leaf cuisine label under this region.
    var allCuisines: [String] {
        groups.flatMap(\.cuisines)
    }

    /// True when this region has no sub-cuisines and acts as a simple leaf toggle.
    var isLeaf: Bool {
        allCuisines.isEmpty
    }
}

// MARK: - Hierarchy Definition

enum CuisineHierarchy {
    /// The full two-level hierarchy used by the filter UI.
    ///
    /// Top-level entries are continents and countries, interleaved so that
    /// country entries appear beneath their parent continent for visual grouping.
    static let regions: [CuisineRegion] = [
        // MARK: - 🌏 Asia (continent)

        CuisineRegion(name: "🌏 Asia", isContinent: true, groups: [
            CuisineGroup(name: "Japanese", cuisines: [
                "Japanese", "Sushi", "Ramen", "Udon", "Soba", "Tempura",
                "Tonkatsu", "Yakiniku", "Yakitori", "Shabu-Shabu", "Izakaya",
                "Washoku", "Okonomiyaki", "Takoyaki", "Gyudon", "Donburi",
                "Teppanyaki", "Kaiseki", "Kushikatsu", "Yoshoku"
            ]),
            CuisineGroup(name: "Chinese", cuisines: [
                "Chinese", "Dim Sum", "Cantonese", "Szechuan", "Hotpot", "Dumpling"
            ]),
            CuisineGroup(name: "Korean", cuisines: [
                "Korean", "Korean BBQ", "Korean Fried Chicken"
            ]),
            CuisineGroup(name: "Thai", cuisines: []),
            CuisineGroup(name: "Vietnamese", cuisines: [
                "Vietnamese", "Pho", "Bánh Mì"
            ]),
            CuisineGroup(name: "Filipino", cuisines: []),
            CuisineGroup(name: "Indonesian", cuisines: []),
            CuisineGroup(name: "Malaysian", cuisines: []),
            CuisineGroup(name: "Singaporean", cuisines: []),
            CuisineGroup(name: "Taiwanese", cuisines: []),
            CuisineGroup(name: "Indian", cuisines: [
                "Indian", "Curry", "Biryani"
            ]),
            CuisineGroup(name: "Nepali", cuisines: []),
            CuisineGroup(name: "Pakistani", cuisines: []),
            CuisineGroup(name: "Sri Lankan", cuisines: []),
            CuisineGroup(name: "Tibetan", cuisines: []),
            CuisineGroup(name: "Afghan", cuisines: []),
            CuisineGroup(name: "Boba Tea", cuisines: [])
        ]),

        // MARK: Country entries under Asia (only countries with sub-cuisines)

        CuisineRegion(name: "🇯🇵 Japanese", isContinent: false, groups: [
            CuisineGroup(name: "Japanese", cuisines: [
                "Japanese", "Sushi", "Ramen", "Udon", "Soba", "Tempura",
                "Tonkatsu", "Yakiniku", "Yakitori", "Shabu-Shabu", "Izakaya",
                "Washoku", "Okonomiyaki", "Takoyaki", "Gyudon", "Donburi",
                "Teppanyaki", "Kaiseki", "Kushikatsu", "Yoshoku"
            ])
        ]),
        CuisineRegion(name: "🇨🇳 Chinese", isContinent: false, groups: [
            CuisineGroup(name: "Chinese", cuisines: [
                "Chinese", "Dim Sum", "Cantonese", "Szechuan", "Hotpot", "Dumpling"
            ])
        ]),
        CuisineRegion(name: "🇰🇷 Korean", isContinent: false, groups: [
            CuisineGroup(name: "Korean", cuisines: [
                "Korean", "Korean BBQ", "Korean Fried Chicken"
            ])
        ]),
        CuisineRegion(name: "🇻🇳 Vietnamese", isContinent: false, groups: [
            CuisineGroup(name: "Vietnamese", cuisines: [
                "Vietnamese", "Pho", "Bánh Mì"
            ])
        ]),
        CuisineRegion(name: "🇮🇳 Indian", isContinent: false, groups: [
            CuisineGroup(name: "Indian", cuisines: [
                "Indian", "Curry", "Biryani"
            ])
        ]),

        // MARK: - 🌍 Middle East & Africa (continent)

        CuisineRegion(name: "🌍 Middle East & Africa", isContinent: true, groups: [
            CuisineGroup(name: "Middle Eastern", cuisines: [
                "Middle Eastern", "Lebanese", "Turkish", "Persian",
                "Israeli", "Egyptian", "Shawarma", "Falafel", "Kebab"
            ]),
            CuisineGroup(name: "African", cuisines: [
                "African", "Moroccan", "Ethiopian", "South African"
            ])
        ]),

        // MARK: Country entries under Middle East & Africa (only countries with sub-cuisines)

        CuisineRegion(name: "🇱🇧 Lebanese", isContinent: false, groups: [
            CuisineGroup(name: "Lebanese", cuisines: [
                "Lebanese", "Shawarma", "Falafel", "Kebab"
            ])
        ]),
        CuisineRegion(name: "🇹🇷 Turkish", isContinent: false, groups: [
            CuisineGroup(name: "Turkish", cuisines: [
                "Turkish", "Kebab"
            ])
        ]),
        CuisineRegion(name: "🇮🇱 Israeli", isContinent: false, groups: [
            CuisineGroup(name: "Israeli", cuisines: [
                "Israeli", "Falafel"
            ])
        ]),

        // MARK: - 🌍 Europe (continent)

        CuisineRegion(name: "🌍 Europe", isContinent: true, groups: [
            CuisineGroup(name: "Italian", cuisines: [
                "Italian", "Pizza", "Pasta"
            ]),
            CuisineGroup(name: "French", cuisines: [
                "French", "Crêperie"
            ]),
            CuisineGroup(name: "Spanish", cuisines: [
                "Spanish", "Tapas"
            ]),
            CuisineGroup(name: "Greek", cuisines: [
                "Greek", "Mediterranean"
            ]),
            CuisineGroup(name: "British", cuisines: [
                "British", "Fish & Chips", "Gastropub", "Pub"
            ]),
            CuisineGroup(name: "Irish", cuisines: [
                "Irish", "Pub"
            ]),
            CuisineGroup(name: "German", cuisines: ["German"]),
            CuisineGroup(name: "Portuguese", cuisines: ["Portuguese"]),
            CuisineGroup(name: "Scandinavian", cuisines: ["Scandinavian"]),
            CuisineGroup(name: "Polish", cuisines: ["Polish"]),
            CuisineGroup(name: "Hungarian", cuisines: ["Hungarian"]),
            CuisineGroup(name: "Austrian", cuisines: ["Austrian"]),
            CuisineGroup(name: "Swiss", cuisines: [
                "Swiss", "Fondue"
            ]),
            CuisineGroup(name: "Belgian", cuisines: [
                "Belgian", "Waffles"
            ]),
            CuisineGroup(name: "Dutch", cuisines: ["Dutch"]),
            CuisineGroup(name: "Georgian", cuisines: ["Georgian"]),
            CuisineGroup(name: "Russian", cuisines: ["Russian"])
        ]),

        // MARK: Country entries under Europe (only countries with sub-cuisines)

        CuisineRegion(name: "🇮🇹 Italian", isContinent: false, groups: [
            CuisineGroup(name: "Italian", cuisines: [
                "Italian", "Pizza", "Pasta"
            ])
        ]),
        CuisineRegion(name: "🇫🇷 French", isContinent: false, groups: [
            CuisineGroup(name: "French", cuisines: [
                "French", "Crêperie"
            ])
        ]),
        CuisineRegion(name: "🇪🇸 Spanish", isContinent: false, groups: [
            CuisineGroup(name: "Spanish", cuisines: [
                "Spanish", "Tapas"
            ])
        ]),
        CuisineRegion(name: "🇬🇷 Greek", isContinent: false, groups: [
            CuisineGroup(name: "Greek", cuisines: [
                "Greek", "Mediterranean"
            ])
        ]),
        CuisineRegion(name: "🇬🇧 British", isContinent: false, groups: [
            CuisineGroup(name: "British", cuisines: [
                "British", "Fish & Chips", "Gastropub", "Pub"
            ])
        ]),
        CuisineRegion(name: "🇮🇪 Irish", isContinent: false, groups: [
            CuisineGroup(name: "Irish", cuisines: [
                "Irish", "Pub"
            ])
        ]),
        CuisineRegion(name: "🇨🇭 Swiss", isContinent: false, groups: [
            CuisineGroup(name: "Swiss", cuisines: [
                "Swiss", "Fondue"
            ])
        ]),
        CuisineRegion(name: "🇧🇪 Belgian", isContinent: false, groups: [
            CuisineGroup(name: "Belgian", cuisines: [
                "Belgian", "Waffles"
            ])
        ]),

        // MARK: - 🌎 Americas (continent)

        CuisineRegion(name: "🌎 Americas", isContinent: true, groups: [
            CuisineGroup(name: "American", cuisines: [
                "American", "Burger", "Steakhouse", "Diner", "Soul Food",
                "Cajun", "Creole", "Wings", "Hot Dog", "Donuts",
                "Hawaiian", "Poke"
            ]),
            CuisineGroup(name: "Mexican", cuisines: [
                "Mexican", "Tacos", "Tex-Mex"
            ]),
            CuisineGroup(name: "Brazilian", cuisines: ["Brazilian"]),
            CuisineGroup(name: "Colombian", cuisines: ["Colombian"]),
            CuisineGroup(name: "Argentinian", cuisines: ["Argentinian"]),
            CuisineGroup(name: "Venezuelan", cuisines: ["Venezuelan"]),
            CuisineGroup(name: "Cuban", cuisines: ["Cuban"]),
            CuisineGroup(name: "Peruvian", cuisines: ["Peruvian"]),
            CuisineGroup(name: "Caribbean", cuisines: ["Caribbean"])
        ]),

        // MARK: Country entries under Americas (only countries with sub-cuisines)

        CuisineRegion(name: "🇺🇸 American", isContinent: false, groups: [
            CuisineGroup(name: "American", cuisines: [
                "American", "Burger", "Steakhouse", "Diner", "Soul Food",
                "Cajun", "Creole", "Wings", "Hot Dog", "Donuts",
                "Hawaiian", "Poke"
            ])
        ]),
        CuisineRegion(name: "🇲🇽 Mexican", isContinent: false, groups: [
            CuisineGroup(name: "Mexican", cuisines: [
                "Mexican", "Tacos", "Tex-Mex"
            ])
        ]),

        // MARK: - 🥗 Dietary (top-level group)

        CuisineRegion(name: "🥗 Dietary", isContinent: true, groups: [
            CuisineGroup(name: "Dietary", cuisines: [
                "Vegetarian", "Vegan", "Halal", "Kosher", "Organic"
            ])
        ]),

        // MARK: - 🍽 General (top-level group)

        CuisineRegion(name: "🍽 General", isContinent: true, groups: [
            CuisineGroup(name: "Mains", cuisines: [
                "Seafood", "BBQ", "Noodle", "Sandwich", "Fried Chicken", "Deli"
            ]),
            CuisineGroup(name: "Breakfast & Brunch", cuisines: [
                "Breakfast", "Brunch", "Waffles", "Pancakes"
            ]),
            CuisineGroup(name: "Café & Dessert", cuisines: [
                "Café", "Bakery", "Ice Cream", "Dessert", "Juice Bar"
            ]),
            CuisineGroup(name: "Drinks", cuisines: [
                "Wine Bar"
            ])
        ])
    ]
}
