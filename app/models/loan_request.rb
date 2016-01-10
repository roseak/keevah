class LoanRequest < ActiveRecord::Base
  validates :title, :description, :amount,
    :requested_by_date, :repayment_begin_date,
    :repayment_rate, :contributed, presence: true
  has_many :orders
  has_many :loan_requests_contributors
  has_many :users, through: :loan_requests_contributors
  has_many :loan_requests_categories
  has_many :categories, through: :loan_requests_categories
  belongs_to :user
  enum status: %w(active funded)
  enum repayment_rate: %w(monthly weekly)
  before_create :assign_default_image

  def assign_default_image
    Rails.cache.fetch("images-#{self.id}") do
      self.image_url = DefaultImages.random if self.image_url.to_s.empty?
    end
  end

  def owner
    Rails.cache.fetch("owner-#{self.id}") do
      self.user.name
    end
  end

  def requested_by
    Rails.cache.fetch("request-by-#{self.id}") do
      self.requested_by_date.strftime("%B %d, %Y")
    end
  end

  def updated_formatted
    Rails.cache.fetch("updated-#{self.id}") do
      self.updated_at.strftime("%B %d, %Y")
    end
  end

  def repayment_begin
    Rails.cache.fetch("repayment-start-#{self.id}") do
      self.repayment_begin_date.strftime("%B %d, %Y")
    end
  end

  def funding_remaining
    Rails.cache.fetch("remaining-#{self.id}") do
      amount - contributed
    end
  end

  def self.projects_with_contributions
    Rails.cache.fetch("projects-contributors-#{self.id}")
    where("contributed > ?", 0)
  end

  def list_project_contributors
    Rails.cache.fetch("contributors-#{self.id}", expires_in: 1.hour) do
      project_contributors.map(&:name).to_sentence
    end
  end

  def progress_percentage
    Rails.cache.fetch("percent-#{self.id}") do
      ((1.00 - (funding_remaining.to_f / amount.to_f)) * 100).to_i
    end
  end

  def minimum_payment
    Rails.cache.fetch("min-pay-#{self.id}") do
      if repayment_rate == "weekly"
        (contributed - repayed) / 12
      else
        (contributed - repayed) / 3
      end
    end
  end

  def repayment_due_date
    Rails.cache.fetch("due-date-#{self.id}") do
      (repayment_begin_date + 12.weeks).strftime("%B %d, %Y")
    end
  end

  def pay!(amount, borrower)
    Rails.cache.fetch("pay-#{self.id}") do
      repayment_percentage = (amount / contributed.to_f)
      project_contributors.each do |lender|
        repayment = lender.contributed_to(self).first.contribution * repayment_percentage
        lender.increment!(:purse, repayment)
        borrower.decrement!(:purse, repayment)
        self.increment!(:repayed, repayment)
      end
    end
  end

  def remaining_payments
    Rails.cache.fetch("remain-pay-#{self.id}") do
      (contributed - repayed) / minimum_payment
    end
  end

  def project_contributors
    Rails.cache.fetch("loan_contributors-#{self.id}", expires_in: 1.hour) do
      LoanRequestsContributor.where(loan_request_id: self.id).pluck(:user_id).map do |user_id|
        User.find(user_id)
      end
    end
  end

  def related_projects
    LoanRequest.includes(:categories).where(categories: {id: self.categories[0].id}).order('RANDOM()').limit(4)
  end
end
