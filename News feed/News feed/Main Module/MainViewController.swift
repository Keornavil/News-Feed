//
//  MainViewController.swift
//  News feed
//
//  Created by Василий Максимов on 21.11.2025.
//

import UIKit
import Combine

final class MainViewController: UIViewController {
    private let viewModel: MainViewModelProtocol
    private let tableView = UITableView()
    private let refreshControl = UIRefreshControl()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(viewModel: MainViewModelProtocol) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        setupTableView()
        setupLayout()
        setupActivityIndicator()
        setupPullToRefresh()
        bindViewModel()
        viewModel.loadPage(reset: true)
    }
    
    // MARK: - Bindings
    
    private func bindViewModel() {
        viewModel.itemsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self else { return }

                self.tableView.reloadData()
                if items.isEmpty {
                    self.activityIndicator.startAnimating()
                } else {
                    self.activityIndicator.stopAnimating()
                }
                self.refreshControl.endRefreshing()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Activity Indicator
    
    private func setupActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
        
        // Поверх таблицы
        view.bringSubviewToFront(activityIndicator)
    }
    
    // MARK: - Pull To Refresh
    
    private func setupPullToRefresh() {
        tableView.refreshControl = refreshControl
        refreshControl.addTarget(self,
                                 action: #selector(handlePullToRefresh),
                                 for: .valueChanged)
    }
    
    @objc private func handlePullToRefresh() {
        // Как ты просил: сразу обновляем таблицу
        tableView.reloadData()
        
        // Дёргаем первую страницу.
        // Индикатор тут не трогаем — он привязан только к empty/не empty.
        viewModel.loadPage(reset: true)
    }
}

// MARK: - TableView Delegate & DataSource

extension MainViewController: UITableViewDelegate, UITableViewDataSource {
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(CustomCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        
        tableView.separatorStyle = .singleLine
        tableView.keyboardDismissMode = .onDragWithAccessory
        tableView.tableFooterView = UIView()
    }
    
    private func setupLayout() {
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
    }
    
    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.countOfNews()
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: "cell",
            for: indexPath
        ) as? CustomCell else {
            fatalError("Failed to dequeue CustomCell")
        }
        
        let item = viewModel.newsItem(at: indexPath.row)
        cell.configure(with: item)
        
        return cell
    }
    
    // MARK: - Pagination trigger
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let visibleHeight = scrollView.bounds.size.height
        
        guard contentHeight > 0 else { return }
        
        if offsetY > contentHeight - visibleHeight * 1.2 {
            viewModel.loadPage(reset: false)
        }
    }
}

// MARK: - Custom Table View Cell

final class CustomCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let avatarView = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupSubviews()
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension CustomCell {
    func setupSubviews() {
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 25
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        bodyLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(avatarView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(bodyLabel)
    }
    
    func setupLayout() {
        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            avatarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
            avatarView.widthAnchor.constraint(equalToConstant: 50),
            avatarView.heightAnchor.constraint(equalToConstant: 50),
            
            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            bodyLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
}

extension CustomCell {
    func configure(with item: NewsData) {
        titleLabel.text = item.title
        bodyLabel.text = item.body
        
        if let data = item.data {
            avatarView.image = UIImage(data: data)
        } else {
            avatarView.image = UIImage(systemName: "photo")
        }
    }
}
